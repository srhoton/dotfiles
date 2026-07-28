#!/bin/bash
#
# guard-destructive-git.sh - PreToolUse(Bash) hook for Claude Code
#
# Blocks git operations that would silently discard UNCOMMITTED work:
#   git reset --hard | git checkout -- <path> | git checkout . |
#   git restore <path> | git clean -f | git stash (push forms)
# ...but only when the target repo actually has uncommitted changes.
#
# Branch operations (git checkout <branch>, git checkout -b, git switch),
# read-only stash subcommands, and anything on a clean tree all pass through.
#
# Motivation: a `git checkout` during mutation testing once destroyed an entire
# session's uncommitted work. Prose rules did not prevent it; this does.
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

GITRE='git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?'
DESTRUCTIVE=""

# git reset --hard  — always destructive
if echo "$CMD" | grep -qE "${GITRE}[[:space:]]+reset\b[^|;&]*--hard"; then
  DESTRUCTIVE="git reset --hard"
fi

# git checkout -- <path>   or   git checkout .
# (NOT `git checkout <branch>` / `git checkout -b <new>`)
if echo "$CMD" | grep -qE "${GITRE}[[:space:]]+checkout([[:space:]]+-[^[:space:]]+)*[[:space:]]+(--[[:space:]]|\.([[:space:]]|\$))"; then
  DESTRUCTIVE="git checkout -- <path>"
fi

# git restore <path>  — unless it is only --staged (that just unstages)
if echo "$CMD" | grep -qE "${GITRE}[[:space:]]+restore\b"; then
  if ! echo "$CMD" | grep -qE "restore[^|;&]*--staged"; then
    DESTRUCTIVE="git restore"
  fi
fi

# git clean with a force flag (-f, -fd, -xdf, --force). `-n` dry-run passes.
if echo "$CMD" | grep -qE "${GITRE}[[:space:]]+clean\b[^|;&]*-[a-zA-Z]*f"; then
  DESTRUCTIVE="git clean -f"
fi

# git stash push forms only; list/show/pop/apply/drop/branch/clear are safe
if echo "$CMD" | grep -qE "${GITRE}[[:space:]]+stash\b"; then
  if ! echo "$CMD" | grep -qE "stash[[:space:]]+(list|show|pop|apply|drop|branch|clear)\b"; then
    DESTRUCTIVE="git stash"
  fi
fi

[ -z "$DESTRUCTIVE" ] && exit 0

# ---- Which repo does this act on? -------------------------------------------
TARGET=$(echo "$CMD" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+([^[:space:]]+).*/\1/p' | head -1)
if [ -z "$TARGET" ]; then
  TARGET=$(echo "$CMD" | sed -nE 's/^[[:space:]]*cd[[:space:]]+([^[:space:]&;|]+).*/\1/p' | head -1)
fi
[ -z "$TARGET" ] && TARGET="$PWD"
TARGET="${TARGET/#\~/$HOME}"
TARGET="${TARGET%\"}"; TARGET="${TARGET#\"}"
TARGET="${TARGET%\'}"; TARGET="${TARGET#\'}"

# Can't identify a repo -> nothing to protect, allow.
git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

DIRTY=$(git -C "$TARGET" status --porcelain 2>/dev/null)
[ -z "$DIRTY" ] && exit 0   # clean tree: nothing can be lost

{
  echo "BLOCKED: '$DESTRUCTIVE' in a repo with uncommitted changes ($TARGET)."
  echo ""
  echo "This would discard work that exists nowhere else. Uncommitted now:"
  printf '%s\n' "$DIRTY" | head -20
  echo ""
  echo "Do one of these instead:"
  echo "  1. Commit the WIP first:  git -C \"$TARGET\" add -A && git -C \"$TARGET\" commit -m 'wip'"
  echo "  2. Copy the file(s) to a temp path, then restore from that copy."
  echo "  3. If the changes really are disposable, say so and let the USER run the command."
} >&2
exit 2
