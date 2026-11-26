#!/bin/bash
#
# Tests for hooks/guard-agent-model.sh. Synthetic JSON inputs only.
# Usage: bash hooks/tests/guard-agent-model.sh
# Override the hook under test with HOOK=/path/to/copy.sh (used for mutation checks).

HOOK="${HOOK:-$(cd "$(dirname "$0")/.." && pwd)/guard-agent-model.sh}"
PASS=0
FAIL=0

# run_hook AGENT [MODEL] -> sets RC and ERR
run_hook() {
  local json
  if [ $# -ge 2 ]; then
    json="{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"$1\",\"model\":\"$2\"}}"
  else
    json="{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"$1\"}}"
  fi
  ERR=$(printf '%s' "$json" | bash "$HOOK" 2>&1 >/dev/null)
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

# code-quality-reviewer is pinned to Sonnet
run_hook code-quality-reviewer sonnet;            expect "quality + sonnet allowed" 0
run_hook code-quality-reviewer claude-sonnet-5-5; expect "quality + full sonnet id allowed" 0
run_hook code-quality-reviewer;                   expect "quality + no model allowed" 0
run_hook code-quality-reviewer opus;              expect "quality + opus blocked" 2
expect_contains "quality block names Sonnet" "pinned to Sonnet"
run_hook code-quality-reviewer haiku;             expect "quality + haiku blocked" 2

# the other reviewers and the verifier stay pinned to Opus
for a in functional-reviewer adr-compliance-reviewer performance-reviewer data-side-effects-reviewer finding-verifier; do
  run_hook "$a" opus;   expect "$a + opus allowed" 0
  run_hook "$a" sonnet; expect "$a + sonnet blocked" 2
  run_hook "$a" haiku;  expect "$a + haiku blocked" 2
  run_hook "$a";        expect "$a + no model allowed" 0
done
run_hook functional-reviewer sonnet
expect_contains "opus block names Opus" "pinned to Opus"

# implementer stays on Sonnet
run_hook implementer sonnet; expect "implementer + sonnet allowed" 0
run_hook implementer opus;   expect "implementer + opus blocked" 2
expect_contains "implementer block says writes code" "writes code"

# unlisted agents and malformed input pass through
run_hook Explore haiku; expect "unlisted agent passes" 0
ERR=$(printf '%s' 'not json' | bash "$HOOK" 2>&1 >/dev/null); RC=$?
expect "garbage input passes" 0
ERR=$(printf '' | bash "$HOOK" 2>&1 >/dev/null); RC=$?
expect "empty input passes" 0

echo
echo "guard-agent-model: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
