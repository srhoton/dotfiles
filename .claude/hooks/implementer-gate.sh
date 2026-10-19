#!/bin/bash
#
# implementer-gate.sh - SubagentStop hook for the `implementer` agent
#
# Registered as `hooks: Stop:` in agents/implementer.md frontmatter (Claude Code
# converts Stop to SubagentStop for subagents). Runs `repo-gate` in the agent's
# working directory. If the gate is red it blocks the first stop and feeds the
# failure excerpt back, forcing exactly ONE retry. A second stop always passes
# (stop_hook_active loop guard), so this is a nudge, not a guarantee: the
# orchestrator's own `repo-gate` re-run remains the authority on whether the
# work is green.
#
# Passes (exit 0) when: stop_hook_active is true (loop guard), the cwd is not in
# a git work tree, the gate passes, repo-gate reports no recognizable project
# (exit 2), repo-gate is missing, or repo-gate fails for any other reason
# (infrastructure errors must never trap the agent).
#
# Test seam: IMPLEMENTER_GATE_BIN overrides the repo-gate path.
#
# Exit 2 = block stopping, stderr is fed back to the agent. Exit 0 = allow.
#

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

PARSED=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print('1' if d.get('stop_hook_active') else '0')
    print(d.get('cwd') or '')
except Exception:
    print('0')
    print('')
" 2>/dev/null) || exit 0

ACTIVE=$(printf '%s\n' "$PARSED" | sed -n '1p')
CWD=$(printf '%s\n' "$PARSED" | sed -n '2p')

# Already continuing because of a previous block: let it stop.
[ "$ACTIVE" = "1" ] && exit 0

[ -z "$CWD" ] && CWD="$PWD"
git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

GATE="${IMPLEMENTER_GATE_BIN:-$HOME/.claude/bin/repo-gate}"
if [ ! -x "$GATE" ]; then
  echo "implementer-gate: $GATE not executable; skipping gate." >&2
  exit 0
fi

OUT=$("$GATE" -C "$CWD" 2>&1)
RC=$?

case "$RC" in
  0) exit 0 ;;
  2) exit 0 ;;   # no recognizable project
  1)
    {
      echo "REPO-GATE failed; fix these before finishing:"
      printf '%s\n' "$OUT" | tail -n 40
    } >&2
    exit 2
    ;;
  *)
    echo "implementer-gate: repo-gate exited $RC (infrastructure error); not blocking." >&2
    exit 0
    ;;
esac
