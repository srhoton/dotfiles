#!/bin/bash
#
# pre-commit-checks.sh - PreToolUse hook for Claude Code
#
# Intercepts `git commit` Bash commands and runs formatters + tests
# before allowing the commit to proceed.
#
# Reads tool input JSON from stdin. Exits 0 to allow, non-zero to block.
#

shopt -s extglob 2>/dev/null

# Read the tool input from stdin
INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

# Extract the command from the JSON input
COMMAND=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input') or d.get('input') or {}
    print(ti.get('command', ''))
except Exception:
    pass
" 2>/dev/null) || exit 0

# If we couldn't parse, pass through
[ -z "$COMMAND" ] && exit 0

# Only intercept git commit commands, including compound forms like
# `cd repo && git commit ...` (not git notes, git commit-tree, etc.)
if ! echo "$COMMAND" | grep -qE '(^|[;&|])[[:space:]]*git[[:space:]]+commit\b'; then
  exit 0
fi

echo "Pre-commit hook: Running formatters and tests..." >&2

# Detect project type and run appropriate checks
FAILED=0

if [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
  # Java/Gradle project
  echo "Detected Java/Gradle project. Running spotlessApply..." >&2
  if [ -f "./gradlew" ]; then
    if ./gradlew spotlessApply 2>&1 >&2; then
      echo "Spotless formatting applied." >&2
      git add -u 2>/dev/null || true
    else
      echo "ERROR: spotlessApply failed." >&2
      FAILED=1
    fi

    if [ $FAILED -eq 0 ]; then
      echo "Running tests..." >&2
      if ! ./gradlew test 2>&1 >&2; then
        echo "ERROR: Tests failed. Fix test failures before committing." >&2
        FAILED=1
      fi
    fi
  fi

elif [ -f "package.json" ]; then
  # Node project
  if [ -f "bun.lockb" ] || [ -f "bun.lock" ]; then
    RUNNER="bun"
  elif [ -f "pnpm-lock.yaml" ]; then
    RUNNER="pnpm"
  else
    RUNNER="npm"
  fi

  echo "Detected Node project (using $RUNNER). Running tests..." >&2
  if ! "$RUNNER" test 2>&1 >&2; then
    echo "ERROR: Tests failed. Fix test failures before committing." >&2
    FAILED=1
  fi

elif [ -f "go.mod" ]; then
  # Go project
  echo "Detected Go project. Running gofmt and tests..." >&2
  command -v gofmt >/dev/null 2>&1 && gofmt -w . 2>&1 >&2 || true
  git add -u 2>/dev/null || true

  if ! go test ./... 2>&1 >&2; then
    echo "ERROR: Tests failed. Fix test failures before committing." >&2
    FAILED=1
  fi

elif [ -f "pyproject.toml" ] || [ -f "requirements.txt" ]; then
  # Python project
  echo "Detected Python project. Running ruff format and pytest..." >&2
  if command -v ruff >/dev/null 2>&1; then
    ruff format . 2>&1 >&2 || true
    git add -u 2>/dev/null || true
  fi

  if command -v pytest >/dev/null 2>&1; then
    if ! pytest 2>&1 >&2; then
      echo "ERROR: Tests failed. Fix test failures before committing." >&2
      FAILED=1
    fi
  fi

elif [ -f "main.tf" ] || compgen -G "*.tf" >/dev/null 2>&1; then
  # Terraform project
  echo "Detected Terraform project. Running fmt and validate..." >&2
  if command -v terraform >/dev/null 2>&1; then
    terraform fmt -recursive 2>&1 >&2 || true
    git add -u 2>/dev/null || true

    if ! terraform validate 2>&1 >&2; then
      echo "ERROR: Terraform validation failed. Fix before committing." >&2
      FAILED=1
    fi
  fi

else
  # Unknown project type, pass through
  exit 0
fi

if [ $FAILED -ne 0 ]; then
  echo "" >&2
  echo "Pre-commit checks FAILED. Commit blocked." >&2
  exit 1
fi

echo "Pre-commit checks passed." >&2
exit 0
