#!/bin/bash
#
# Tests for pr-ci-wait. A stub gh (selected via the GH env var) answers each
# `gh pr checks` poll from a scripted sequence (poll-N.json, last one repeats,
# counter in a file) and records `gh run view` calls. PR_CI_WAIT_SLEEP=0 skips
# real sleeping and PR_CI_WAIT_FAKE_CLOCK advances elapsed time per poll, so the
# suite needs no wall-clock time and never touches GitHub.
#
# Usage: bin/tests/pr-ci-wait.sh        (exit 1 if any case fails)

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
WAIT="$HERE/../pr-ci-wait"
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

check() { # NAME EXIT-STATUS-OF-CONDITION
  if [ "$2" -eq 0 ]; then PASS=$((PASS + 1)); echo "ok   $1"
  else FAIL=$((FAIL + 1)); echo "FAIL $1"; fi
}

cat > "$WORK/gh" <<'STUB'
#!/bin/bash
D="$STUB_DIR"
case "$1 $2" in
  "pr checks")
    n=$(( $(cat "$D/counter" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$D/counter"
    f="$D/poll-$n.json"; [ -e "$f" ] || f=$(ls "$D"/poll-*.json | sort -t- -k2 -n | tail -1)
    if [ "$(cat "$f")" = "ERROR" ]; then echo "error connecting to api.invalid" >&2; exit 1; fi
    cat "$f"
    grep -q '"bucket": *"fail"' "$f" && exit 1
    grep -q '"bucket": *"pending"' "$f" && exit 8
    exit 0 ;;
  "run view")
    echo "$*" >> "$D/runview.log"
    for i in $(seq 1 60); do echo "failed log line $i"; done ;;
  *) echo "stub gh: unexpected call: $*" >&2; exit 99 ;;
esac
STUB
chmod +x "$WORK/gh"

# chk NAME STATE BUCKET [LINK] -> one check object
chk() { printf '{"name":"%s","state":"%s","bucket":"%s","link":"%s","workflow":"CI"}' "$1" "$2" "$3" "${4:-}"; }

new_case() { STUB_DIR="$WORK/$1"; mkdir -p "$STUB_DIR"; export STUB_DIR; }
poll() { echo "[$2]" > "$STUB_DIR/poll-$1.json"; } # N JSON-OBJECTS-COMMA-SEPARATED
polls_used() { cat "$STUB_DIR/counter"; }

run() { GH="$WORK/gh" PR_CI_WAIT_SLEEP=0 PR_CI_WAIT_FAKE_CLOCK=${CLOCK:-10} "$WAIT" 7 -R o/r "$@"; }

# --- pending -> pass, pass: exit 0 after the flicker guard ---------------------
new_case green
poll 1 "$(chk build IN_PROGRESS pending),$(chk lint SUCCESS pass)"
poll 2 "$(chk build SUCCESS pass),$(chk lint SUCCESS pass),$(chk docs SKIPPED skipping)"
poll 3 "$(chk build SUCCESS pass),$(chk lint SUCCESS pass),$(chk docs SKIPPED skipping)"
OUT=$(run 2>&1); RC=$?
check "green: exit 0" $([ "$RC" -eq 0 ]; echo $?)
check "green: exactly 3 polls (pending, pass, confirming pass)" $([ "$(polls_used)" -eq 3 ]; echo $?)
check "green: change lines for pending -> done" $(echo "$OUT" | grep -qF "CI / build  - -> IN_PROGRESS" && echo "$OUT" | grep -qF "CI / build  IN_PROGRESS -> SUCCESS"; echo $?)
check "green: unchanged checks not reprinted" $([ "$(echo "$OUT" | grep -c 'CI / lint')" -eq 1 ]; echo $?)
check "green: change lines carry elapsed time" $(echo "$OUT" | grep -qE '^\+00:20  CI / build  IN_PROGRESS -> SUCCESS$'; echo $?)
check "green: summary" $(echo "$OUT" | grep -qF "all 3 check(s) passed or were skipped"; echo $?)

# --- flicker: a lone terminal snapshot is not trusted ----------------------------
new_case flicker
poll 1 "$(chk build SUCCESS pass)"
poll 2 "$(chk build IN_PROGRESS pending)"
poll 3 "$(chk build SUCCESS pass)"
poll 4 "$(chk build SUCCESS pass)"
run >/dev/null 2>&1; RC=$?
check "flicker: pass, pending, pass, pass -> exit 0 only after 4 polls" $([ "$RC" -eq 0 ] && [ "$(polls_used)" -eq 4 ]; echo $?)

# --- pending -> fail: exit 1 and failed log tail -----------------------------------
new_case red
poll 1 "$(chk build IN_PROGRESS pending),$(chk e2e IN_PROGRESS pending)"
poll 2 "$(chk build FAILURE fail https://example.invalid/o/r/actions/runs/12345/job/99),$(chk e2e SUCCESS pass)"
OUT=$(run 2>&1); RC=$?
check "red: exit 1" $([ "$RC" -eq 1 ]; echo $?)
check "red: gh run view called for run 12345 with -R and --log-failed" $([ "$(cat "$STUB_DIR/runview.log")" = "run view 12345 -R o/r --log-failed" ]; echo $?)
check "red: only the last 40 log lines printed" $(echo "$OUT" | grep -qxF "failed log line 60" && echo "$OUT" | grep -qxF "failed log line 21" && ! echo "$OUT" | grep -qxF "failed log line 20"; echo $?)
check "red: failed check named" $(echo "$OUT" | grep -qF "CI / build  FAILURE"; echo $?)

# --- failed check with no actions link: exit 1, no run view ------------------------
new_case redlink
poll 1 "$(chk external FAILURE fail https://example.invalid/status/1)"
run >/dev/null 2>&1; RC=$?
check "failure without /actions/runs link: exit 1, no gh run view" $([ "$RC" -eq 1 ] && [ ! -e "$STUB_DIR/runview.log" ]; echo $?)

# --- cancelled counts as failure; two failed jobs of one run fetch the log once ------
new_case cancel
poll 1 "$(chk a FAILURE fail https://example.invalid/o/r/actions/runs/5/job/1),$(chk b FAILURE fail https://example.invalid/o/r/actions/runs/5/job/2),$(chk c CANCELLED cancel)"
run >/dev/null 2>&1; RC=$?
check "cancel+fail: exit 1, run log fetched once" $([ "$RC" -eq 1 ] && [ "$(wc -l < "$STUB_DIR/runview.log")" -eq 1 ]; echo $?)

new_case cancelonly
poll 1 "$(chk a SUCCESS pass),$(chk c CANCELLED cancel)"
run >/dev/null 2>&1; RC=$?
check "a cancelled check alone: exit 1" $([ "$RC" -eq 1 ]; echo $?)

# --- always pending: timeout, exit 2 ----------------------------------------------
new_case timeout
poll 1 "$(chk build IN_PROGRESS pending),$(chk lint SUCCESS pass)"
OUT=$(CLOCK=20 run --max-minutes 1 2>&1); RC=$?
check "timeout: exit 2" $([ "$RC" -eq 2 ]; echo $?)
check "timeout: stops at the fake-clock deadline (3 polls x 20s = 1 min)" $([ "$(polls_used)" -eq 3 ]; echo $?)
check "timeout: lists the still-pending check only" $(echo "$OUT" | grep -qF "timed out after 1 min" && echo "$OUT" | grep -qE '^  CI / build  IN_PROGRESS$' && ! echo "$OUT" | grep -qE '^  CI / lint'; echo $?)

# --- no checks: exit 3 after 3 polls -----------------------------------------------
new_case empty
poll 1 ""
OUT=$(run 2>&1); RC=$?
check "no checks: exit 3 after exactly 3 polls" $([ "$RC" -eq 3 ] && [ "$(polls_used)" -eq 3 ]; echo $?)

new_case late
poll 1 ""
poll 2 ""
poll 3 "$(chk build SUCCESS pass)"
poll 4 "$(chk build SUCCESS pass)"
run >/dev/null 2>&1; RC=$?
check "checks appearing on poll 3: no exit 3, ends 0" $([ "$RC" -eq 0 ]; echo $?)

# --- gh failing repeatedly: exit 4 ---------------------------------------------------
new_case ghdown
echo ERROR > "$STUB_DIR/poll-1.json"
run >/dev/null 2>&1; RC=$?
check "gh fails 3 polls in a row: exit 4" $([ "$RC" -eq 4 ] && [ "$(polls_used)" -eq 3 ]; echo $?)

# --- backoff doubling to the cap, and the last wait clipped to the deadline -----------
SLEEPS=$(python3 - "$WAIT" <<'PY'
import argparse, importlib.machinery, importlib.util, os, sys
sys.dont_write_bytecode = True
os.environ["PR_CI_WAIT_FAKE_CLOCK"] = "10"
os.environ["GH"] = "/bin/false"  # never reached: fetch_checks is replaced below
loader = importlib.machinery.SourceFileLoader("pr_ci_wait", sys.argv[1])
spec = importlib.util.spec_from_loader("pr_ci_wait", loader)
m = importlib.util.module_from_spec(spec); loader.exec_module(m)
m.fetch_checks = lambda pr, repo: [{"name": "b", "state": "PENDING", "bucket": "pending", "workflow": "CI"}]
slept = []
m.sleep = slept.append
args = argparse.Namespace(pr="7", repo=None, max_minutes=1.0, interval_start=5.0, interval_max=20.0)
print(m.wait(args), slept)
PY
)
SLEEPS=$(echo "$SLEEPS" | tail -1)
check "backoff: 5,10,20,20 then clipped to 10s left, exit 2" $([ "$SLEEPS" = "2 [5.0, 10.0, 20.0, 20.0, 10.0]" ]; echo $?)

echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
