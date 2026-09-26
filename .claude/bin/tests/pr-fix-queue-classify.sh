#!/bin/bash
#
# Classifier tests for pr-fix-queue. Each case builds a GraphQL response, feeds
# it through PR_FIX_QUEUE_FIXTURE (no GitHub call, no state access, no launch),
# and asserts on the plan row the classifier prints.
#
# Usage: bin/tests/pr-fix-queue-classify.sh        (exit 1 if any case fails)

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
QUEUE="$HERE/../pr-fix-queue"
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

# fixture NAME 'PYTHON-EXPR'  — the expression is a list of PR dicts built with
# pr(...) and comment(...) below. The viewer is always "me".
fixture() {
  python3 - "$WORK/$1.json" "$2" <<'PY'
import json, sys

def comment(id, login="rev", typename="User", created="2026-09-21T10:00:00Z",
            edited=None, minimized=False, reactions=()):
    # reactions: (content, login, createdAt) tuples
    groups = {}
    for content, who, _ in reactions:
        groups[content] = groups.get(content, False) or who == "me"
    return {
        "databaseId": id, "createdAt": created, "lastEditedAt": edited,
        "isMinimized": minimized, "author": {"login": login, "__typename": typename},
        "reactionGroups": [{"content": k, "viewerHasReacted": v} for k, v in groups.items()],
        "reactions": {"nodes": [{"content": c, "createdAt": t, "user": {"login": w}}
                                for c, w, t in reactions]},
    }

def thread(id, first="rev", last="rev", last_id="L1", typename="User"):
    return {"id": id, "isResolved": False, "isOutdated": False,
            "firstComment": {"nodes": [{"author": {"login": first, "__typename": typename}}]},
            "lastComment": {"nodes": [{"id": last_id, "author": {"login": last}}]}}

def pr(num, comments=(), threads=(), total=None, mergeable="MERGEABLE", draft=False,
       decision="REVIEW_REQUIRED", reviews=(), latest=None):
    # reviews: (id, state) per reviewer's latest approve/request (latestOpinionatedReviews);
    # latest overrides latestReviews, which GitHub can return without a standing request.
    rv = lambda rows: {"nodes": [{"id": i, "state": st} for i, st in rows]}
    return {
        "number": num, "title": "t%d" % num, "isDraft": draft,
        "updatedAt": "2026-09-21T12:00:00Z", "headRefOid": "h%d" % num,
        "headRefName": "feature-%d" % num, "isCrossRepository": False,
        "mergeable": mergeable, "reviewDecision": decision,
        "repository": {"nameWithOwner": "acme/repo", "name": "repo"},
        "baseRef": {"name": "master", "target": {"oid": "b0"}},
        "latestOpinionatedReviews": rv(reviews),
        "latestReviews": rv(reviews if latest is None else latest),
        "reviewThreads": {"nodes": list(threads)},
        "comments": {"totalCount": len(comments) if total is None else total,
                     "nodes": list(comments)},
    }

prs = eval(sys.argv[2])
doc = {"data": {"viewer": {"login": "me", "pullRequests": {"nodes": prs}}}}
with open(sys.argv[1], "w") as fh:
    json.dump(doc, fh)
PY
}

run() {  # NAME [queue args...] -> plan rows on stdout
  local name="$1"; shift
  PR_FIX_QUEUE_FIXTURE="$WORK/$name.json" PR_FIX_STATE="$WORK/state-must-not-exist.json" \
    "$QUEUE" "$@" 2>&1
}

ok()   { PASS=$((PASS + 1)); echo "ok    $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL  $1"; echo "      got: $2"; }

expect() {  # CASE OUTPUT PATTERN  (extended regex that must match)
  if printf '%s\n' "$2" | grep -Eq -- "$3"; then ok "$1"; else bad "$1 (wanted /$3/)" "$2"; fi
}
reject() {  # CASE OUTPUT PATTERN  (extended regex that must NOT match)
  if printf '%s\n' "$2" | grep -Eq -- "$3"; then bad "$1 (did not want /$3/)" "$2"; else ok "$1"; fi
}

T=$'\t'

fixture standingcr '[pr(40, decision="CHANGES_REQUESTED", reviews=[("R1","CHANGES_REQUESTED"),("R2","APPROVED")], latest=[("R2","APPROVED")])]'
out=$(run standingcr)
expect "standing change request hidden from latestReviews is a candidate" "$out" "^CAND${T}acme/repo${T}repo${T}40${T}"
expect "  fingerprint names the requesting review" "$out" "cr:R1"
expect "  label says changes-requested" "$out" "changes-requested"

fixture approvedonly '[pr(41, decision="APPROVED", reviews=[("R3","APPROVED")])]'
out=$(run approvedonly)
reject "an approval alone is not a change request" "$out" "changes-requested"

fixture unanswered '[pr(1, [comment(100)])]'
out=$(run unanswered)
expect "unanswered human comment is a candidate" "$out" "^CAND${T}acme/repo${T}repo${T}1${T}"
expect "  fingerprint carries id@created and mr:0" "$out" "ic:100@2026-09-21T10:00:00Z\|mr:0${T}"
expect "  label says 1 comment(s)" "$out" "1 comment\(s\) — t1"

fixture rocket '[pr(2, [comment(100, reactions=[("ROCKET","me","2026-09-21T11:00:00Z")])])]'
out=$(run rocket)
expect "my ROCKET handles the comment" "$out" "^CLEAR${T}acme/repo${T}repo${T}2${T}"
reject "  and it is not a candidate" "$out" "^CAND"

fixture thumbs '[pr(3, [comment(100, reactions=[("THUMBS_UP","me","2026-09-21T11:00:00Z")])])]'
out=$(run thumbs)
expect "my THUMBS_UP does not handle it" "$out" "^CAND${T}.*ic:100@"

fixture otherrocket '[pr(4, [comment(100, reactions=[("ROCKET","someone","2026-09-21T11:00:00Z")])])]'
out=$(run otherrocket)
expect "someone else's ROCKET does not handle it" "$out" "^CAND${T}.*ic:100@"

fixture edited '[pr(5, [comment(100, edited="2026-09-21T12:00:00Z", reactions=[("ROCKET","me","2026-09-21T11:00:00Z")])])]'
out=$(run edited)
expect "edit after my ROCKET re-opens it" "$out" "^CAND${T}"
expect "  and the fingerprint uses the edit time" "$out" "ic:100@2026-09-21T12:00:00Z"

fixture rerocket '[pr(6, [comment(100, edited="2026-09-21T12:00:00Z", reactions=[("ROCKET","me","2026-09-21T13:00:00Z")])])]'
out=$(run rerocket)
expect "ROCKET placed after the edit handles it" "$out" "^CLEAR${T}"

fixture myreply '[pr(7, [comment(100), comment(200, login="me", created="2026-09-21T11:00:00Z")])]'
out=$(run myreply)
expect "a later reply of mine does NOT handle it" "$out" "^CAND${T}.*ic:100@"
expect "  but it moves the fingerprint (mr:200)" "$out" "\|mr:200${T}"

fixture bot '[pr(8, [comment(100, login="amazon-q", typename="Bot")])]'
out=$(run bot)
expect "bot conversation comment is ignored" "$out" "^CLEAR${T}"
out=$(run bot --include-bots)
expect "  even with --include-bots" "$out" "^CLEAR${T}"

fixture minimized '[pr(9, [comment(100, minimized=True), comment(101, login="me")])]'
out=$(run minimized)
expect "minimized and my own comments are ignored" "$out" "^CLEAR${T}"

fixture both '[pr(10, [comment(100)], threads=[thread("T1")])]'
out=$(run both)
expect "threads + comments: both labels" "$out" "1 thread\(s\), 1 comment\(s\)"
expect "  and both fingerprint parts" "$out" "th:T1:L1\|ic:100@[^|]*\|mr:0"

fixture botthread '[pr(11, threads=[thread("T1", first="ci-bot", typename="Bot")])]'
out=$(run botthread)
expect "bot thread ignored by default" "$out" "^CLEAR${T}"
out=$(run botthread --include-bots)
expect "  but --include-bots still applies to threads" "$out" "^CAND${T}.*th:T1:L1"

fixture truncated '[pr(12, [comment(100)], total=73)]'
out=$(run truncated)
expect "more than 50 comments is called out" "$out" "only newest 50 comments checked"

fixture unknown '[pr(13, mergeable="UNKNOWN")]'
start=$(date +%s)
out=$(run unknown)
took=$(( $(date +%s) - start ))
expect "UNKNOWN mergeability is SKIP with its reason intact" "$out" "^SKIP${T}acme/repo${T}repo${T}13${T}.*mergeability still UNKNOWN"
reject "  and is not CLEAR (state must survive)" "$out" "^CLEAR"
if [ "$took" -lt 2 ]; then ok "  fixture mode does not sleep through the re-poll (${took}s)"; else bad "  fixture mode slept" "${took}s"; fi

fixture draft '[pr(14, [comment(100)], draft=True), pr(15, [comment(100)])]'
out=$(run draft)
expect "draft fixture ran (its non-draft sibling is a candidate)" "$out" "^CAND${T}acme/repo${T}repo${T}15${T}"
reject "  draft PR produces no row at all (no CLEAR, state untouched)" "$out" "${T}14${T}"

fixture busyclear '[pr(16, [comment(100, reactions=[("ROCKET","me","2026-09-21T11:00:00Z")])], total=73)]'
out=$(run busyclear)
expect "CLEAR on a truncated comment list says so" "$out" "^CLEAR${T}.*73 conversation comments, only the newest 50"

# Every row must have all 9 columns. The shell reads rows with IFS=tab, and tab
# is IFS whitespace, so an empty column collapses and shifts the ones after it.
cols_ok() {  # CASE OUTPUT
  if printf '%s\n' "$2" | awk -F'\t' 'NF!=9{bad=1} /\t\t/{bad=1} END{exit bad}'; then ok "$1"
  else bad "$1" "$2"; fi
}
cols_ok "SKIP row has 9 non-empty columns"  "$(run unknown)"
cols_ok "CLEAR row has 9 non-empty columns" "$(run rocket)"
cols_ok "CAND row has 9 non-empty columns"  "$(run unanswered)"

if [ -e "$WORK/state-must-not-exist.json" ] || [ -e "$WORK/state-must-not-exist.json.lock" ]; then
  bad "fixture mode touched the state file" "$(ls "$WORK")"
else
  ok "fixture mode never touches the state file"
fi

# ---- state handling -----------------------------------------------------------
# Fixture mode exits before any state access, so these run the real script with
# `gh` and `claude` stubbed on PATH, a private state file, TMUX unset, and -m 0
# so that nothing can launch (every candidate is DEFERRED).
STUB="$WORK/stub"; mkdir -p "$STUB"
printf '#!/bin/bash\ncat "$STUB_JSON"\n' > "$STUB/gh"
printf '#!/bin/bash\necho "claude stub must never run" >&2; exit 9\n' > "$STUB/claude"
chmod +x "$STUB/gh" "$STUB/claude"

real() {  # FIXTURE-NAME [queue args...]
  local name="$1"; shift
  env -u TMUX PATH="$STUB:$PATH" STUB_JSON="$WORK/$name.json" \
    PR_FIX_STATE="$WORK/state.json" PR_FIX_DIR="$WORK/clones" "$QUEUE" "$@" 2>&1
}
seed() {  # "key=age_hours" ...   (writes $WORK/state.json)
  python3 - "$WORK/state.json" "$@" <<'PY'
import datetime, json, sys
now = datetime.datetime.now(datetime.timezone.utc)
data = {}
for spec in sys.argv[2:]:
    key, age = spec.rsplit("=", 1)
    stamp = (now - datetime.timedelta(hours=float(age))).strftime("%Y-%m-%dT%H:%M:%SZ")
    data[key] = {"launched_at": stamp, "head_sha": "x", "fingerprint": "old", "attempts": 1}
json.dump(data, open(sys.argv[1], "w"))
PY
}
keys() { python3 -c 'import json,sys; print(" ".join(sorted(json.load(open(sys.argv[1])))))' "$WORK/state.json"; }

fixture mixed '[pr(1, [comment(100)]), pr(2, [comment(100, reactions=[("ROCKET","me","2026-09-21T11:00:00Z")])])]'

seed "acme/repo#1=5" "acme/repo#2=5" "other/repo#99=5"
real mixed -n -m 0 >/dev/null
expect "dry run deletes no state" "$(keys)" "^acme/repo#1 acme/repo#2 other/repo#99$"

out=$(real mixed -m 0)
expect "real run drops only the clear PR's record" "$(keys)" "^acme/repo#1 other/repo#99$"
expect "  and the blocked PR is DEFERRED, not launched" "$out" "^DEFERRED +acme/repo#1 "
reject "  and the claude stub never ran" "$out" "claude stub must never run"

seed "acme/repo#2=0.5"
real mixed -m 0 >/dev/null
expect "a clear PR still inside the cooldown keeps its record" "$(keys)" "^acme/repo#2$"

fixture reblocked '[pr(2, [comment(100)])]'
out=$(real reblocked -m 5)
expect "  so a new comment during that window is IN-FLIGHT, not a second launch" "$out" "^IN-FLIGHT +acme/repo#2 "
reject "  and the claude stub never ran" "$out" "claude stub must never run"

seed "acme/repo#1=5" "other/repo#99=5"
out=$(real mixed --retry "other/repo#99" -m 0)
expect "--retry removes exactly that key" "$(keys)" "^acme/repo#1$"
expect "  and says so" "$out" "forgot state for other/repo#99"

out=$(real mixed --retry "acme/typo#1" -m 0)
expect "--retry on an unknown key says nothing was recorded" "$out" "no state recorded for acme/typo#1"
expect "  and leaves the state alone" "$(keys)" "^acme/repo#1$"

rm -f "$WORK/state.json"
out=$(real mixed --retry "acme/repo#1" -m 0)
expect "--retry with no state file says that, not 'check the spelling'" "$out" "no readable state file"

# A malformed record must not abort the sweep and strand the rest of the batch.
python3 - "$WORK/state.json" <<'PY'
import json, sys
json.dump({"acme/repo#2": {"launched_at": None, "fingerprint": "old", "attempts": 1},
           "other/repo#99": {"launched_at": 12345}}, open(sys.argv[1], "w"))
PY
out=$(real mixed -m 0)
expect "a record with a null launched_at is swept, not a crash" "$(keys)" "^other/repo#99$"
reject "  and no python traceback reaches the terminal" "$out" "Traceback"

out=$(real mixed --retry "acme/repo#1" --clean); rc=$?
expect "--retry with --clean is refused" "$out" "cannot be combined"
if [ "$rc" = 1 ]; then ok "  with exit 1"; else bad "  with exit 1" "rc=$rc"; fi

echo
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" = 0 ]
