#!/bin/bash
#
# Tests for aws-target. A fake `aws` (AWS_TARGET_AWS) records its argv and prints a
# canned get-caller-identity response. The account ids and profiles checked here are
# the ones in the CLAUDE.md profile table; no real AWS call is made.
#
# Usage: bin/tests/aws-target.sh        (exit 1 if any case fails)

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
AT="${AWS_TARGET_SCRIPT:-$HERE/../aws-target}"
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tmp"
PASS=0; FAIL=0
OUT=""; ERR=""; RC=0

ok()  { PASS=$((PASS + 1)); echo "PASS  $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL  $1"; echo "      $2"; echo "      stdout: $OUT" | head -5; echo "      stderr: $ERR" | head -5; }

assert_eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi; }
assert_out_has()   { if printf '%s\n' "$OUT" | grep -qF -- "$2"; then ok "$1"; else bad "$1" "stdout missing: $2"; fi; }
assert_out_lacks() { if printf '%s\n' "$OUT" | grep -qF -- "$2"; then bad "$1" "stdout unexpectedly has: $2"; else ok "$1"; fi; }
assert_err_has()   { if printf '%s\n' "$ERR" | grep -qF -- "$2"; then ok "$1"; else bad "$1" "stderr missing: $2"; fi; }
assert_err_lacks() { if printf '%s\n' "$ERR" | grep -qF -- "$2"; then bad "$1" "stderr unexpectedly has: $2"; else ok "$1"; fi; }

calls() { if [ -f "$ARGV_LOG" ]; then wc -l < "$ARGV_LOG" | tr -d ' '; else echo 0; fi; }

ARGV_LOG="$WORK/aws.argv"

# Fake aws: logs argv (one line per call). FAKE_ACCOUNT shapes the response;
# FAKE_FAIL_MSG makes it fail with that stderr text; FAKE_RAW replaces stdout.
FAKE_AWS="$WORK/fake-aws"
cat > "$FAKE_AWS" <<'EOF'
#!/bin/bash
echo "$*" >> "$FAKE_ARGV_LOG"
if [ -n "${FAKE_FAIL_MSG:-}" ]; then echo "$FAKE_FAIL_MSG" >&2; exit "${FAKE_FAIL_RC:-255}"; fi
if [ -n "${FAKE_RAW:-}" ]; then printf '%s\n' "$FAKE_RAW"; exit 0; fi
printf '{\n    "UserId": "AROAFAKE:someone",\n    "Account": "%s",\n    "Arn": "arn:aws:sts::%s:assumed-role/Fake/someone"\n}\n' "$FAKE_ACCOUNT" "$FAKE_ACCOUNT"
EOF
chmod +x "$FAKE_AWS"

# run_at [args...] : stdout -> OUT, stderr -> ERR, exit -> RC. Fake behaviour is
# passed through the caller's prefix assignments.
run_at() {
  local errf="$WORK/stderr.txt"
  OUT=$(AWS_TARGET_AWS="${AT_AWS:-$FAKE_AWS}" FAKE_ARGV_LOG="$ARGV_LOG" TMPDIR="$WORK/tmp" "$AT" "$@" 2>"$errf" < /dev/null)
  RC=$?
  ERR=$(cat "$errf")
}

new_case() { ARGV_LOG="$WORK/aws-$1.argv"; rm -f "$ARGV_LOG"; }

unset AWS_TARGET_AWS AWS_PROFILE

# ---- 1. each env maps to its profile and account -------------------------------------
check_env() { # env profile account
  new_case "map-$1"
  FAKE_ACCOUNT="$3" run_at "$1"
  assert_eq "$1 - exit 0" 0 "$RC"
  assert_eq "$1 - stdout is exactly the export line" "export AWS_PROFILE='$2'" "$OUT"
  assert_err_has "$1 - status line on stderr" "aws-target: $1 -> $2 (account $3)"
  assert_eq "$1 - aws called once, with --profile $2" "sts get-caller-identity --profile $2 --output json" "$(head -1 "$ARGV_LOG")"
  assert_eq "$1 - exactly one aws call" 1 "$(calls)"
}
check_env dev      fb-dev-non-prod/Admin       147997133155
check_env qa       fb-qa-non-prod/ReadOnly     343218192518
check_env stage    fb-stage-non-prod/ReadOnly  528757793739
check_env prod     fb-live-us-prod/ReadOnly    211125509520
check_env demo     fb-demo-us-prod/ReadOnly    979667334065
check_env datalake fb-datalake-prod/Admin      230514136789

# ---- 2. eval round trip --------------------------------------------------------------
new_case eval
FAKE_ACCOUNT=211125509520 run_at prod
unset AWS_PROFILE
eval "$OUT"
assert_eq "eval - AWS_PROFILE set from stdout" "fb-live-us-prod/ReadOnly" "${AWS_PROFILE:-}"
assert_eq "eval - stdout is a single line" 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
unset AWS_PROFILE

# ---- 3. account mismatch -------------------------------------------------------------
new_case mismatch
FAKE_ACCOUNT=211125509520 run_at demo     # prod's account answered for the demo profile
assert_eq "mismatch - exit 1" 1 "$RC"
assert_eq "mismatch - nothing on stdout" "" "$OUT"
assert_err_has "mismatch - names the expected account" "expected 979667334065"
assert_err_has "mismatch - names the actual account" "got 211125509520"
assert_err_lacks "mismatch - no login hint (the session is fine)" "aws sso login"
FAKE_RAW='{"Arn":"x"}' run_at qa
assert_eq "no Account in response - exit 1" 1 "$RC"
assert_eq "no Account in response - nothing on stdout" "" "$OUT"
assert_err_has "no Account in response - says so" "<none in response>"

# ---- 4. expired or missing session ---------------------------------------------------
new_case expired
FAKE_FAIL_MSG="The SSO session associated with this profile has expired or is otherwise invalid." run_at stage
assert_eq "expired - exit 2" 2 "$RC"
assert_eq "expired - nothing on stdout" "" "$OUT"
assert_err_has "expired - login hint" "run: aws sso login --profile fb-stage-non-prod/ReadOnly"
assert_err_has "expired - aws message relayed" "has expired"
FAKE_FAIL_MSG="Unable to locate credentials" run_at datalake
assert_eq "no credentials - exit 2" 2 "$RC"
assert_err_has "no credentials - login hint names the datalake profile" "run: aws sso login --profile fb-datalake-prod/Admin"
FAKE_FAIL_MSG="boom" FAKE_FAIL_RC=1 run_at qa
assert_eq "any other sts failure - exit 2" 2 "$RC"
assert_eq "any other sts failure - nothing on stdout" "" "$OUT"

# ---- 5. usage ------------------------------------------------------------------------
new_case usage
run_at sandbox
assert_eq "unknown env - exit 3" 3 "$RC"
assert_eq "unknown env - nothing on stdout" "" "$OUT"
assert_eq "unknown env - aws never called" 0 "$(calls)"
run_at
assert_eq "no env - exit 3" 3 "$RC"
run_at --check
assert_eq "--check without env - exit 3" 3 "$RC"
run_at prod qa
assert_eq "two envs - exit 3" 3 "$RC"
run_at prod --profile fb-qa-non-prod/Admin
assert_eq "--profile is not an option - exit 3" 3 "$RC"
assert_eq "--profile - aws never called" 0 "$(calls)"
AT_AWS="$WORK/no-such-aws" run_at prod
assert_eq "missing aws - exit 3" 3 "$RC"
OUT=$("$AT" --help 2>&1); RC=$?
assert_eq "help - exit 0" 0 "$RC"
assert_out_has "help - prints header usage" "aws-target <dev|qa|stage|prod|demo|datalake> [--check]"
assert_out_lacks "help - stops at end of header" "set -uo pipefail"

# ---- 6. --check ----------------------------------------------------------------------
new_case check
FAKE_ACCOUNT=343218192518 run_at qa --check
assert_eq "--check - exit 0 on match" 0 "$RC"
assert_eq "--check - nothing on stdout" "" "$OUT"
assert_eq "--check - still calls aws" 1 "$(calls)"
FAKE_ACCOUNT=343218192518 run_at --check qa
assert_eq "--check before env - exit 0" 0 "$RC"
assert_eq "--check before env - nothing on stdout" "" "$OUT"
FAKE_ACCOUNT=1 run_at qa --check
assert_eq "--check - exit 1 on mismatch" 1 "$RC"
FAKE_FAIL_MSG="expired" run_at qa --check
assert_eq "--check - exit 2 on failure" 2 "$RC"
assert_eq "--check - failure prints nothing on stdout" "" "$OUT"
assert_err_has "--check - failure still prints login hint" "run: aws sso login --profile fb-qa-non-prod/ReadOnly"

# ---- 7. Admin is never selected outside dev and datalake ----------------------------
new_case admin
for e in qa stage prod demo; do
  FAKE_ACCOUNT=0 run_at "$e"
done
assert_eq "qa/stage/prod/demo - no Admin profile ever passed to aws" 0 "$(grep -c '/Admin' "$ARGV_LOG")"
assert_eq "qa/stage/prod/demo - four calls logged" 4 "$(calls)"

echo
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
