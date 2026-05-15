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
    cmd = d.get('input', {}).get('command', '')
    print(cmd)
except Exception:
    pass
" 2>/dev/null) || exit 0

# If we couldn't parse or it's not a git commit, pass through
[ -z "$COMMAND" ] && exit 0

# Only intercept git commit commands (not git notes, etc.)
case "$COMMAND" in
  git\ commit|git\ commit\ *|*\ git\ commit) true ;;
  *) exit 0 ;;
esac

printf 'Pre-commit hook: Running formatters and tests...\n' >&2

stage_formatted_files() {
  git diff --name-only -z | xargs -0 git add --
}

# Detect project type and run appropriate checks
FAILED=0

if [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
  # Java/Gradle project
  printf 'Detected Java/Gradle project. Running spotlessApply...\n' >&2
  if command -v gradlew >/dev/null 2>&1 || [ -f "./gradlew" ]; then
    if ./gradlew spotlessApply 2>&1 >&2; then
      printf 'Spotless formatting applied.\n' >&2
      stage_formatted_files 2>/dev/null || true
    else
      printf 'ERROR: spotlessApply failed.\n' >&2
      FAILED=1
    fi
  fi

  if [ $FAILED -eq 0 ]; then
    printf 'Running tests...\n' >&2
    if ! ./gradlew test 2>&1 >&2; then
      printf 'ERROR: Tests failed. Fix test failures before committing.\n' >&2
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

  printf "Detected Node project (using $RUNNER). Running tests...\n" >&2
  if ! "$RUNNER" test 2>&1 >&2; then
    printf 'ERROR: Tests failed. Fix test failures before committing.\n' >&2
    FAILED=1
  fi

elif [ -f "go.mod" ]; then
  # Go project
  printf 'Detected Go project. Running gofmt and tests...\n' >&2
  command -v gofmt >/dev/null 2>&1 && gofmt -w . 2>&1 >&2 || true
  stage_formatted_files 2>/dev/null || true

  if ! go test ./... 2>&1 >&2; then
    printf 'ERROR: Tests failed. Fix test failures before committing.\n' >&2
    FAILED=1
  fi

elif [ -f "pyproject.toml" ] || [ -f "requirements.txt" ]; then
  # Python project
  printf 'Detected Python project. Running ruff format and pytest...\n' >&2
  if command -v ruff >/dev/null 2>&1; then
    ruff format . 2>&1 >&2 || true
    stage_formatted_files 2>/dev/null || true
  fi

  if command -v pytest >/dev/null 2>&1; then
    if ! pytest 2>&1 >&2; then
      printf 'ERROR: Tests failed. Fix test failures before committing.\n' >&2
      FAILED=1
    fi
  fi

elif [ -f "main.tf" ] || compgen -G "*.tf" >/dev/null 2>&1; then
  # Terraform project
  printf 'Detected Terraform project. Running fmt and validate...\n' >&2
  command -v terraform >/dev/null 2>&1 && {
    terraform fmt -recursive 2>&1 >&2 || true
    stage_formatted_files 2>/dev/null || true
    terraform validate 2>&1 >&2 || {
      printf 'ERROR: Terraform validation failed. Fix before committing.\n' >&2
      FAILED=1
    }
  }

else
  # Unknown project type, pass through
  exit 0
fi

if [ $FAILED -ne 0 ]; then
  printf '\nPre-commit checks FAILED. Commit blocked.\n' >&2
  exit 1
fi

printf 'Pre-commit checks passed.\n' >&2
exit 0
