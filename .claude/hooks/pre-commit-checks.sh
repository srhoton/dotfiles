#!/bin/bash
#
# pre-commit-checks.sh - PreToolUse hook for Claude Code
#
# Intercepts `git commit` Bash commands and runs formatters + tests
# before allowing the commit to proceed.
#
# Reads tool input JSON from stdin. Exits 0 to allow, non-zero to block.
#

# Read the tool input from stdin
INPUT=$(cat)

# Extract the command from the JSON input
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('input',{}).get('command',''))" 2>/dev/null)

# If we couldn't parse or it's not a git commit, pass through
if [ -z "$COMMAND" ]; then
  exit 0
fi

# Only intercept git commit commands (not git commit --amend with no message, git notes, etc.)
if ! echo "$COMMAND" | grep -qE '^\s*git\s+commit\b'; then
  exit 0
fi

echo "Pre-commit hook: Running formatters and tests..." >&2

# Detect project type and run appropriate checks
FAILED=0

if [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
  # Java/Gradle project
  echo "Detected Java/Gradle project. Running spotlessApply..." >&2
  if ./gradlew spotlessApply 2>&1 >&2; then
    echo "Spotless formatting applied." >&2
    git add -u 2>/dev/null
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
  if ! $RUNNER test 2>&1 >&2; then
    echo "ERROR: Tests failed. Fix test failures before committing." >&2
    FAILED=1
  fi

elif [ -f "go.mod" ]; then
  # Go project
  echo "Detected Go project. Running gofmt and tests..." >&2
  gofmt -w . 2>&1 >&2
  git add -u 2>/dev/null

  if ! go test ./... 2>&1 >&2; then
    echo "ERROR: Tests failed. Fix test failures before committing." >&2
    FAILED=1
  fi

elif [ -f "pyproject.toml" ] || [ -f "requirements.txt" ]; then
  # Python project
  echo "Detected Python project. Running ruff format and pytest..." >&2
  if command -v ruff &>/dev/null; then
    ruff format . 2>&1 >&2
    git add -u 2>/dev/null
  fi

  if command -v pytest &>/dev/null; then
    if ! pytest 2>&1 >&2; then
      echo "ERROR: Tests failed. Fix test failures before committing." >&2
      FAILED=1
    fi
  fi

elif [ -f "main.tf" ] || ls *.tf 1>/dev/null 2>&1; then
  # Terraform project
  echo "Detected Terraform project. Running fmt and validate..." >&2
  terraform fmt -recursive 2>&1 >&2
  git add -u 2>/dev/null

  if ! terraform validate 2>&1 >&2; then
    echo "ERROR: Terraform validation failed. Fix before committing." >&2
    FAILED=1
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
