#!/bin/bash
#
# Tests for hooks/guard-session-scope.sh using synthetic temp transcripts.
# Usage: bash hooks/tests/guard-session-scope.sh
# Override the hook under test with HOOK=/path/to/copy.sh (used for mutation checks).

HOOK="${HOOK:-$(cd "$(dirname "$0")/.." && pwd)/guard-session-scope.sh}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
PASS=0
FAIL=0

# Transcript lines in the real on-disk form.
DELIVER_LINE='{"type":"user","message":{"role":"user","content":"<command-message>deliver</command-message>\n<command-name>/deliver</command-name>\n<command-args>DP-1</command-args>"},"sessionId":"s"}'
ASSISTANT_LINE='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"working on it"}]},"sessionId":"s"}'
OTHER_USER_LINE='{"type":"user","message":{"role":"user","content":"hello"},"sessionId":"s"}'
# An assistant/tool line that merely quotes the command text (escaped quotes), not a user invocation.
QUOTED_LINE='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"run <command-name>/deliver</command-name> to start"}]}}'

# transcript NAME LINE...: writes $WORK/NAME one line per argument.
transcript() {
  local name="$1"
  shift
  : >"$WORK/$name"
  local l
  for l in "$@"; do printf '%s\n' "$l" >>"$WORK/$name"; done
}

# run_hook PROMPT TRANSCRIPT_PATH -> sets OUT and RC
run_hook() {
  OUT=$(PROMPT="$1" TP="$2" python3 -c '
import json, os
print(json.dumps({"prompt": os.environ["PROMPT"], "transcript_path": os.environ["TP"]}))
' | bash "$HOOK" 2>&1)
  RC=$?
}

expect_pass() { # NAME
  if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
    PASS=$((PASS + 1))
    echo "PASS: $1"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $1 (want exit 0 and empty output, got $RC) $OUT"
  fi
}

expect_block() { # NAME
  local decision
  decision=$(printf '%s' "$OUT" | python3 -c 'import sys, json; print(json.load(sys.stdin).get("decision", ""))' 2>/dev/null)
  if [ "$RC" -eq 0 ] && [ "$decision" = "block" ] && printf '%s' "$OUT" | grep -qF "Start a fresh session" && printf '%s' "$OUT" | grep -qF -- "--same-session"; then
    PASS=$((PASS + 1))
    echo "PASS: $1"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $1 (want exit 0 and block JSON, got $RC) $OUT"
  fi
}

# --- first /deliver in a session passes ---
transcript empty
transcript fresh "$OTHER_USER_LINE" "$ASSISTANT_LINE"
run_hook "/deliver DP-1" "$WORK/empty"; expect_pass "first /deliver (empty transcript) passes"
run_hook "/deliver DP-1" "$WORK/fresh"; expect_pass "first /deliver (no earlier deliver) passes"

# The current prompt may already be flushed to disk with no reply after it.
transcript self_written "$OTHER_USER_LINE" "$ASSISTANT_LINE" "$DELIVER_LINE"
run_hook "/deliver DP-1" "$WORK/self_written"; expect_pass "first /deliver already flushed to transcript passes"

# --- second /deliver is blocked ---
transcript second "$DELIVER_LINE" "$ASSISTANT_LINE" "$OTHER_USER_LINE" "$ASSISTANT_LINE"
run_hook "/deliver DP-2" "$WORK/second"; expect_block "second /deliver is blocked"

transcript second_flushed "$DELIVER_LINE" "$ASSISTANT_LINE" "$DELIVER_LINE"
run_hook "/deliver DP-2" "$WORK/second_flushed"; expect_block "second /deliver blocked when current prompt already flushed"

run_hook "  /deliver DP-2" "$WORK/second"; expect_block "leading whitespace before /deliver still blocked"

# --- --same-session passes ---
run_hook "/deliver DP-2 --same-session" "$WORK/second"; expect_pass "--same-session at end passes"
run_hook "/deliver --same-session DP-2" "$WORK/second"; expect_pass "--same-session before key passes"

# --- non-/deliver prompts pass ---
run_hook "please run /deliver for me" "$WORK/second"; expect_pass "prompt mentioning /deliver mid-text passes"
run_hook "/deliverable DP-2" "$WORK/second"; expect_pass "/deliverable (different command) passes"
run_hook "/reviewit 12" "$WORK/second"; expect_pass "other slash command passes"
run_hook "fix the bug" "$WORK/second"; expect_pass "plain prompt passes"

# --- text that only quotes the command does not count ---
transcript quoted "$QUOTED_LINE" "$ASSISTANT_LINE"
run_hook "/deliver DP-1" "$WORK/quoted"; expect_pass "quoted command text in assistant line does not count"

# --- errors and ambiguity pass ---
run_hook "/deliver DP-2" "$WORK/does-not-exist"; expect_pass "missing transcript passes"
run_hook "/deliver DP-2" ""; expect_pass "empty transcript_path passes"
OUT=$(printf '%s' 'not json' | bash "$HOOK" 2>&1); RC=$?; expect_pass "garbage input passes"
OUT=$(printf '' | bash "$HOOK" 2>&1); RC=$?; expect_pass "empty input passes"
OUT=$(printf '%s' '{"prompt":"/deliver DP-2"}' | bash "$HOOK" 2>&1); RC=$?; expect_pass "missing transcript_path field passes"

echo
echo "guard-session-scope: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
