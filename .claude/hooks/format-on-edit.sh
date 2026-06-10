#!/bin/bash
# PostToolUse hook: formats files based on extension after Claude edits them.
# Reads tool input JSON from stdin. Silent on failure, always exits 0.

shopt -s extglob 2>/dev/null

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
    command -v npx &>/dev/null && (cd "$FILE_DIR" && npx --no-install eslint --fix "$FILE_PATH" 2>/dev/null) || true
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

exit 0
