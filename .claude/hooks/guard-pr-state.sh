#!/bin/bash
#
# guard-pr-state.sh - PreToolUse(Bash) hook for Claude Code
#
# Blocks `git push` when the current branch belongs to a PR that is already
# MERGED or CLOSED. Commits have been pushed to merged-PR branches, where they
# reach no open review. CLAUDE.md already says "never update a closed PR" —
# this enforces it.
#
# Passes through when: there is no PR for the branch, `gh` is unavailable, or
# anything is ambiguous. A brand-new branch must always be pushable.
#
# Exit 2 = block, stderr is fed back to Claude. Exit 0 = allow.
#

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

CMD=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input') or d.get('input') or {}
    print(ti.get('command', ''))
except Exception:
    pass
" 2>/dev/null) || exit 0
[ -z "$CMD" ] && exit 0

# Only `git push`.
echo "$CMD" | grep -qE '(^|[;&|]|&&)[[:space:]]*git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push\b' || exit 0

command -v gh >/dev/null 2>&1 || exit 0

TARGET=$(echo "$CMD" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+([^[:space:]]+).*/\1/p' | head -1)
if [ -z "$TARGET" ]; then
  TARGET=$(echo "$CMD" | sed -nE 's/^[[:space:]]*cd[[:space:]]+([^[:space:]&;|]+).*/\1/p' | head -1)
fi
[ -z "$TARGET" ] && TARGET="$PWD"
TARGET="${TARGET/#\~/$HOME}"
TARGET="${TARGET%\"}"; TARGET="${TARGET#\"}"
TARGET="${TARGET%\'}"; TARGET="${TARGET#\'}"

git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

BRANCH=$(git -C "$TARGET" rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ -z "$BRANCH" ] || [ "$BRANCH" = "HEAD" ]; then
  exit 0
fi

STATE=$(cd "$TARGET" 2>/dev/null && gh pr view "$BRANCH" --json state -q .state 2>/dev/null)
[ -z "$STATE" ] && exit 0   # no PR, or gh couldn't tell us -> allow

case "$STATE" in
  MERGED|CLOSED)
    URL=$(cd "$TARGET" 2>/dev/null && gh pr view "$BRANCH" --json url -q .url 2>/dev/null)
    {
      echo "BLOCKED: branch '$BRANCH' belongs to a PR that is already $STATE."
      [ -n "$URL" ] && echo "  $URL"
      echo ""
      echo "Pushing here reaches no open review. Per CLAUDE.md, a closed/merged PR"
      echo "requires a NEW branch and a NEW PR:"
      echo "    git -C \"$TARGET\" checkout -b <new-branch>"
      echo "    git -C \"$TARGET\" push -u origin <new-branch>"
      echo "then open a fresh PR against the default branch."
    } >&2
    exit 2
    ;;
esac
exit 0
