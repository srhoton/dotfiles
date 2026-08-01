#!/bin/bash
# PostToolUse hook: formats files based on extension after Claude edits them,
# and SURFACES any lint errors that auto-fix could not repair.
#
# Reads tool input JSON from stdin. Always exits 0 — never makes a successful
# Edit look failed.
#
# Why the JSON output at the end: for PostToolUse, plain stdout is discarded
# (Claude Code parses stdout for JSON only), so `eslint --fix ... 2>/dev/null`
# silently threw away every finding it could not auto-repair — which is where
# real bugs live (a ReDoS-prone regex is not auto-fixable). Emitting
# hookSpecificOutput.additionalContext is the documented non-blocking way to
# put those findings in front of the model on the next request, so they get
# fixed in the same turn instead of surfacing two review rounds later.

shopt -s extglob 2>/dev/null

# Collected lint findings to report back to the model (empty = nothing to say).
LINT_FEEDBACK=""

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

FILE_PATH=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input') or d.get('input') or {}
    print(ti.get('file_path', ''))
except Exception:
    pass
" 2>/dev/null) || exit 0

[ -z "$FILE_PATH" ] && exit 0
[ ! -f "$FILE_PATH" ] && exit 0

# Use file's directory for gradle/terraform so tools find the project root
FILE_DIR=$(dirname "$FILE_PATH")

case "$FILE_PATH" in
  *.java)
    # Walk up from file dir to find nearest gradlew
    DIR="$FILE_DIR"
    while [ "$DIR" != "/" ] && [ ! -f "$DIR/gradlew" ]; do DIR=$(dirname "$DIR"); done
    if [ -f "$DIR/gradlew" ]; then
      (cd "$DIR" && ./gradlew spotlessApply -q 2>/dev/null) || true
    fi
    ;;
  *.ts|*.tsx|*.js|*.jsx)
    # Walk up for the nearest eslint config AND an installed eslint. Both are
    # required: `npx --no-install eslint` exits 1 (not >=2) when the package is
    # missing, so without this guard npm's own error text gets reported as if it
    # were a lint finding.
    ES_DIR=""
    D="$FILE_DIR"
    while [ "$D" != "/" ] && [ -n "$D" ]; do
      for c in eslint.config.js eslint.config.mjs eslint.config.cjs eslint.config.ts \
               .eslintrc .eslintrc.js .eslintrc.cjs .eslintrc.json .eslintrc.yml .eslintrc.yaml; do
        [ -f "$D/$c" ] && { ES_DIR="$D"; break; }
      done
      [ -n "$ES_DIR" ] && break
      D=$(dirname "$D")
    done
    if [ -n "$ES_DIR" ] && [ -x "$ES_DIR/node_modules/.bin/eslint" ]; then
      # --fix repairs what it can; --quiet reports only remaining ERRORS.
      ESLINT_OUT="$(cd "$ES_DIR" && ./node_modules/.bin/eslint --fix --quiet --format unix "$FILE_PATH" 2>&1)"
      ES_RC=$?
      if [ "$ES_RC" -eq 1 ] && [ -n "$ESLINT_OUT" ]; then
        LINT_FEEDBACK="$(printf '%s\n' "$ESLINT_OUT" | grep -v '^$' | grep -v 'npm error' | head -20)"
      fi
    fi
    ;;
  *.tf)
    command -v terraform &>/dev/null && (cd "$FILE_DIR" && terraform fmt "$FILE_PATH" 2>/dev/null) || true
    ;;
  *.go)
    command -v gofmt &>/dev/null && gofmt -w "$FILE_PATH" 2>/dev/null || true
    ;;
  *.py)
    command -v ruff &>/dev/null && (cd "$FILE_DIR" && ruff format "$FILE_PATH" 2>/dev/null) || true
    ;;
esac

# Surface unfixable lint errors to the model (non-blocking). Built with jq/python
# so rule messages and code snippets are JSON-escaped rather than interpolated.
if [ -n "$LINT_FEEDBACK" ]; then
  MSG="ESLint reported errors it could not auto-fix in the file you just edited ($FILE_PATH). Fix them now rather than leaving them for a later review pass:
$LINT_FEEDBACK"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg ctx "$MSG" \
      '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}' 2>/dev/null
  else
    MSG="$MSG" python3 -c 'import json,os; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":os.environ["MSG"]}}))' 2>/dev/null
  fi
fi

exit 0
