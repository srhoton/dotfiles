#!/bin/bash
#
# guard-aws-sso.sh - PreToolUse(Bash) hook for Claude Code
#
# Blocks `aws ...` commands when the credentials for the target profile are
# missing/expired, and reports the exact re-login command. Expired SSO sessions
# have repeatedly blocked verification mid-investigation; failing fast with the
# fix beats discovering it on a rejected API call three steps later.
#
# The check result is cached ~10 minutes per profile so this stays fast.
# `aws sso login` / `aws sso logout` / `aws configure` are never gated.
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

# Only real `aws` CLI invocations.
echo "$CMD" | grep -qE '(^|[;&|]|&&)[[:space:]]*aws[[:space:]]' || exit 0

# Never gate the remedy itself, or purely local config.
echo "$CMD" | grep -qE 'aws[[:space:]]+(sso[[:space:]]+(login|logout)|configure)\b' && exit 0

command -v aws >/dev/null 2>&1 || exit 0

# Resolve which credentials this command will use.
PROF=$(echo "$CMD" | sed -nE 's/.*--profile[[:space:]]+([^[:space:]]+).*/\1/p' | head -1)
if [ -n "$PROF" ]; then
  PROFILE_ARG="--profile $PROF"; LABEL="$PROF"
elif [ -n "${AWS_PROFILE:-}" ]; then
  PROFILE_ARG="--profile $AWS_PROFILE"; LABEL="$AWS_PROFILE"
else
  PROFILE_ARG=""; LABEL="(default credential chain)"
fi

STAMP_DIR="$HOME/.claude/session-env"
mkdir -p "$STAMP_DIR" 2>/dev/null
KEY=$(printf '%s' "$LABEL" | tr -c 'A-Za-z0-9_.-' '_')
STAMP="$STAMP_DIR/.sso-ok-$KEY"

# Verified within the last 10 minutes? Skip the network round-trip.
if [ -f "$STAMP" ]; then
  NOW=$(date +%s)
  THEN=$(stat -f %m "$STAMP" 2>/dev/null || stat -c %Y "$STAMP" 2>/dev/null || echo 0)
  [ $((NOW - THEN)) -lt 600 ] && exit 0
fi

if aws sts get-caller-identity $PROFILE_ARG >/dev/null 2>&1; then
  touch "$STAMP"
  exit 0
fi

{
  echo "BLOCKED: AWS credentials for $LABEL are missing or expired."
  echo "'aws sts get-caller-identity $PROFILE_ARG' failed, so this command would fail too."
  echo ""
  if [ -n "$PROF" ] || [ -n "${AWS_PROFILE:-}" ]; then
    echo "Ask the user to re-authenticate:"
    echo "    aws sso login --profile $LABEL"
    echo "(They can run it inline in Claude Code:  ! aws sso login --profile $LABEL )"
  else
    echo "No --profile was given and AWS_PROFILE is unset. Confirm the intended"
    echo "account with the user, then have them run: aws sso login --profile <p>"
  fi
  echo ""
  echo "Do NOT guess a different profile name. Confirm the target account first"
  echo "(profiles available:  aws configure list-profiles )."
} >&2
exit 2
