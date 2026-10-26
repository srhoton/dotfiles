#!/bin/bash
#
# Tests for hooks/implementer-gate.sh using a fake repo-gate (IMPLEMENTER_GATE_BIN).
# Synthetic inputs only; temp git repos are created and removed.
# Usage: bash hooks/tests/implementer-gate.sh
# Override the hook under test with HOOK=/path/to/copy.sh (used for mutation checks).

HOOK="${HOOK:-$(cd "$(dirname "$0")/.." && pwd)/implementer-gate.sh}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/repo" "$WORK/nongit"
git -C "$WORK/repo" init -q 2>/dev/null
PASS=0
FAIL=0

# fake_gate NAME EXIT_CODE [OUTPUT_LINES]: writes a repo-gate stand-in that
# records its args, prints OUTPUT_LINES numbered lines, and exits EXIT_CODE.
fake_gate() {
  local name="$1" code="$2" lines="${3:-3}"
  cat >"$WORK/$name" <<EOF
#!/bin/bash
echo "\$@" >"$WORK/$name.args"
i=1
while [ \$i -le $lines ]; do echo "gate output line \$i."; i=\$((i + 1)); done
echo "REPO-GATE: FAIL (1 gates)"
exit $code
EOF
  chmod +x "$WORK/$name"
}

# run_hook JSON GATE_BIN -> sets RC and ERR
run_hook() {
  ERR=$(printf '%s' "$1" | IMPLEMENTER_GATE_BIN="$2" bash "$HOOK" 2>&1 >/dev/null)
  RC=$?
}

expect() { # NAME WANT_RC
  if [ "$RC" -eq "$2" ]; then
    PASS=$((PASS + 1))
    echo "PASS: $1"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $1 (want exit $2, got $RC) $ERR"
  fi
}

expect_contains() { # NAME NEEDLE
  if printf '%s' "$ERR" | grep -qF -- "$2"; then
    PASS=$((PASS + 1))
    echo "PASS: $1"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $1 (stderr lacks '$2'): $ERR"
  fi
}

expect_not_contains() { # NAME NEEDLE
  if printf '%s' "$ERR" | grep -qF -- "$2"; then
    FAIL=$((FAIL + 1))
    echo "FAIL: $1 (stderr unexpectedly has '$2')"
  else
    PASS=$((PASS + 1))
    echo "PASS: $1"
  fi
}

REPO_JSON="{\"cwd\":\"$WORK/repo\",\"stop_hook_active\":false}"

fake_gate gate-fail 1 60
fake_gate gate-pass 0
fake_gate gate-noproj 2
fake_gate gate-weird 7

# gate exit 1 blocks, with prefix and a bounded excerpt of the TAIL
run_hook "$REPO_JSON" "$WORK/gate-fail"
expect "gate exit 1 blocks" 2
expect_contains "block message has prefix" "REPO-GATE failed; fix these before finishing:"
expect_contains "excerpt includes final gate line" "REPO-GATE: FAIL (1 gates)"
expect_contains "excerpt keeps late output" "gate output line 60."
expect_not_contains "excerpt drops early output (tail ~40 lines)" "gate output line 5."
LINES=$(printf '%s\n' "$ERR" | wc -l | tr -d ' ')
if [ "$LINES" -le 42 ]; then
  PASS=$((PASS + 1)); echo "PASS: stderr is bounded ($LINES lines)"
else
  FAIL=$((FAIL + 1)); echo "FAIL: stderr too long ($LINES lines)"
fi
if grep -qx -- "-C $WORK/repo" "$WORK/gate-fail.args"; then
  PASS=$((PASS + 1)); echo "PASS: gate invoked with -C <cwd>"
else
  FAIL=$((FAIL + 1)); echo "FAIL: gate args were: $(cat "$WORK/gate-fail.args" 2>&1)"
fi

# passing and non-blocking outcomes
run_hook "$REPO_JSON" "$WORK/gate-pass";   expect "gate exit 0 passes" 0
run_hook "$REPO_JSON" "$WORK/gate-noproj"; expect "gate exit 2 (no project) passes" 0
run_hook "$REPO_JSON" "$WORK/gate-weird";  expect "gate unexpected exit code passes" 0
expect_contains "unexpected exit code leaves a stderr note" "infrastructure error"
run_hook "$REPO_JSON" "$WORK/does-not-exist"; expect "missing gate binary passes" 0

# loop guard: even a failing gate must not block when stop_hook_active is true
rm -f "$WORK/gate-fail.args"
run_hook "{\"cwd\":\"$WORK/repo\",\"stop_hook_active\":true}" "$WORK/gate-fail"
expect "stop_hook_active true passes with failing gate" 0
if [ ! -e "$WORK/gate-fail.args" ]; then
  PASS=$((PASS + 1)); echo "PASS: gate not even run when stop_hook_active"
else
  FAIL=$((FAIL + 1)); echo "FAIL: gate ran despite stop_hook_active"
fi

# non-git cwd passes even with a failing gate
run_hook "{\"cwd\":\"$WORK/nongit\",\"stop_hook_active\":false}" "$WORK/gate-fail"
expect "non-git cwd passes with failing gate" 0

# cwd falls back to $PWD when absent
ERR=$(cd "$WORK/repo" && printf '%s' '{"stop_hook_active":false}' | IMPLEMENTER_GATE_BIN="$WORK/gate-fail" bash "$HOOK" 2>&1 >/dev/null)
RC=$?
expect "missing cwd falls back to PWD (repo) and blocks" 2

# robustness
run_hook "" "$WORK/gate-fail";           expect "empty input passes" 0
ERR=$(cd "$WORK/nongit" && printf '%s' 'not json' | IMPLEMENTER_GATE_BIN="$WORK/gate-fail" bash "$HOOK" 2>&1 >/dev/null)
RC=$?
expect "garbage input falls back to PWD (non-git) and passes" 0

echo
echo "implementer-gate: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
