#!/bin/bash
#
# sessionstart-envdrift.sh - SessionStart hook for Claude Code
#
# If the current repo is a deployable Port stack, inject an
# additionalContext directive so Claude prints the env-drift table on its
# first turn. The hook does NO network I/O — it only emits JSON — so
# session start is never blocked; the Port MCP call happens when Claude
# acts. Emits nothing (no directive) outside a git repo with a remote, or
# on resume/compact (only fresh starts / explicit clear).
#

INPUT=$(cat)
SOURCE=$(printf '%s' "$INPUT" | python3 -c \
  "import sys,json; print(json.load(sys.stdin).get('source',''))" 2>/dev/null)

# Only on a fresh start or explicit /clear — not resume/compact, so the
# table doesn't re-print after every autocompact.
case "$SOURCE" in
  startup|clear|"") ;;
  *) exit 0 ;;
esac

# Must be a git repo with an origin remote.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
git config --get remote.origin.url >/dev/null 2>&1 || exit 0

STACK="$(basename "$PWD")"

CTX="ENV-DRIFT STARTUP CHECK — this repo may be a deployable Port stack named '${STACK}'. On your first response, before addressing the user's request: using the Port MCP, look up the '${STACK}-dev' entity in the stack_environment_status blueprint. If it does NOT exist, do nothing and do not mention this check. If it DOES exist, follow the /envdrift procedure for stack '${STACK}' (read dev/qa/stage/prod/demo short_sha, run ~/.claude/bin/sha-relation, print the drift table), then continue with whatever the user asked. This is read-only — never deploy."

CTX="$CTX" python3 - <<'PY'
import json, os
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": os.environ["CTX"],
    }
}))
PY
exit 0
