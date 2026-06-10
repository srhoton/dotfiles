#!/bin/bash
#
# pr-stale-check.sh - PostToolUse hook for Claude Code (matcher: Bash)
#
# After a `gh pr create` command runs, surface OTHER teams' open PRs in
# the same repo that have gone stale (no activity >3 days), so they don't
# keep getting ignored. Delegates the query to ~/.claude/bin/stale-prs.
#
# Reads tool input JSON from stdin. Emits a PostToolUse additionalContext
# JSON payload when there are stale PRs; otherwise stays silent. Always
# exits 0 — this is a reminder, never a blocker.
#

INPUT=$(cat)

# Extract the command. Read both `tool_input.command` (current docs) and
# `input.command` (what the other hooks on this machine use) so this works
# regardless of payload version.
COMMAND=$(printf '%s' "$INPUT" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print((d.get('tool_input') or d.get('input') or {}).get('command',''))" \
  2>/dev/null)

# Only act on PR-creation commands; pass through everything else.
echo "$COMMAND" | grep -qE '\bgh\s+pr\s+create\b' || exit 0

STALE="$("$HOME/.claude/bin/stale-prs" 3 2>/dev/null || true)"
[ -z "$STALE" ] && exit 0   # nothing stale → stay silent

MSG="STALE PR REMINDER — other open PRs in this repo have had no activity in >3 days. Surface this list to the user verbatim:
$STALE"

MSG="$MSG" python3 - <<'PY'
import json, os
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": os.environ["MSG"],
    }
}))
PY
exit 0
