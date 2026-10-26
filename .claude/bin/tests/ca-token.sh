#!/bin/bash
#
# Tests for ca-token. A fake `aws` (CA_TOKEN_AWS) records its argv and prints a
# canned get-authorization-token response; the clock is pinned with CA_TOKEN_NOW
# and the cache lives in a temp dir (CA_TOKEN_CACHE_DIR). Every token, profile and
# account id here is synthetic; nothing is real.
#
# Usage: bin/tests/ca-token.sh        (exit 1 if any case fails)

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
CT="$HERE/../ca-token"
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

mode_of() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }
calls() { if [ -f "$ARGV_LOG" ]; then wc -l < "$ARGV_LOG" | tr -d ' '; else echo 0; fi; }
iso_of() { date -u -r "$1" +%Y-%m-%dT%H:%M:%S+00:00 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%S+00:00; }

NOW0=1800000000
H=3600
ARGV_LOG="$WORK/aws.argv"

# Fake aws: logs argv (one line per call). FAKE_TOKEN / FAKE_EXP_EPOCH shape the
# response; FAKE_FAIL_MSG makes it fail with that stderr text; FAKE_RAW replaces
# the whole stdout.
FAKE_AWS="$WORK/fake-aws"
cat > "$FAKE_AWS" <<'EOF'
#!/bin/bash
echo "$*" >> "$FAKE_ARGV_LOG"
if [ -n "${FAKE_FAIL_MSG:-}" ]; then echo "$FAKE_FAIL_MSG" >&2; exit "${FAKE_FAIL_RC:-255}"; fi
if [ -n "${FAKE_RAW:-}" ]; then printf '%s\n' "$FAKE_RAW"; exit 0; fi
printf '{"authorizationToken":"%s","expiration":"%s"}\n' "${FAKE_TOKEN:-FAKE-TOKEN-1}" "$FAKE_EXP_ISO"
EOF
chmod +x "$FAKE_AWS"

# run_ct NOW [args...] : stdout -> OUT, stderr -> ERR, exit -> RC. Env for the
# fake is passed through the caller's prefix assignments.
run_ct() {
  local now=$1; shift
  local errf="$WORK/stderr.txt"
  OUT=$(CA_TOKEN_NOW="$now" CA_TOKEN_AWS="${CT_AWS:-$FAKE_AWS}" CA_TOKEN_CACHE_DIR="$CACHE" FAKE_ARGV_LOG="$ARGV_LOG" \
        TMPDIR="$WORK/tmp" "$CT" "$@" 2>"$errf" < /dev/null)
  RC=$?
  ERR=$(cat "$errf")
}

new_case() { # name : fresh cache dir and argv log
  CACHE="$WORK/cache-$1"
  ARGV_LOG="$WORK/aws-$1.argv"
  rm -rf "$CACHE" "$ARGV_LOG"
}

export FAKE_EXP_ISO; FAKE_EXP_ISO=$(iso_of $((NOW0 + 12 * H)))
unset XDG_CACHE_HOME CA_TOKEN_PROFILE CA_TOKEN_DOMAIN CA_TOKEN_OWNER CA_TOKEN_REGION CA_TOKEN_AWS CA_TOKEN_CACHE_DIR CA_TOKEN_NOW

# ---- 1. first call fetches and caches ----------------------------------------------
new_case c1
run_ct $NOW0
assert_eq "first call - exit 0" 0 "$RC"
assert_eq "first call - aws called once" 1 "$(calls)"
assert_eq "first call - argv is the codeartifact call with defaults" \
  "codeartifact get-authorization-token --profile fb-common-non-prod/Repository-ReadOnly --domain fullbay --domain-owner 851725176053 --region us-west-2 --output json" \
  "$(head -1 "$ARGV_LOG")"
assert_eq "first call - cache dir mode 700" 700 "$(mode_of "$CACHE")"
CFILE=$(ls "$CACHE"/ca-token-* 2>/dev/null | head -1)
assert_eq "first call - exactly one cache file" 1 "$(ls "$CACHE" | wc -l | tr -d ' ')"
assert_eq "first call - cache file mode 600" 600 "$(mode_of "${CFILE:-/nonexistent}")"
assert_out_has "first call - status line with 11h cap (expiry is 12h out)" "ca-token: token cached, valid until $(date -u -r $((NOW0 + 11 * H)) +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$((NOW0 + 11 * H))" +%Y-%m-%dT%H:%M:%SZ)"
assert_out_lacks "default output - no token" "FAKE-TOKEN-1"
assert_err_lacks "default stderr - no token" "FAKE-TOKEN-1"

# ---- 2. second call within validity reuses the cache ---------------------------------
run_ct $((NOW0 + 3 * H)) --env gradle
assert_eq "cache reuse - exit 0" 0 "$RC"
assert_eq "cache reuse - aws not called again" 1 "$(calls)"
assert_eq "cache reuse - gradle line carries cached token" "export ORG_GRADLE_PROJECT_codeartifactToken='FAKE-TOKEN-1'" "$OUT"

# ---- 3. expired cache refetches -----------------------------------------------------
FAKE_TOKEN=FAKE-TOKEN-2 run_ct $((NOW0 + 11 * H + 1)) --print
assert_eq "expired cache - aws called again" 2 "$(calls)"
assert_eq "expired cache - new token served" "FAKE-TOKEN-2" "$OUT"

# ---- 4. --refresh forces a fetch ----------------------------------------------------
FAKE_TOKEN=FAKE-TOKEN-3 run_ct $((NOW0 + 11 * H + 2)) --refresh --print
assert_eq "--refresh - aws called despite valid cache" 3 "$(calls)"
assert_eq "--refresh - new token served" "FAKE-TOKEN-3" "$OUT"

# ---- 5. output modes ----------------------------------------------------------------
new_case c5
run_ct $NOW0 --env gradle
assert_eq "--env gradle - exact line" "export ORG_GRADLE_PROJECT_codeartifactToken='FAKE-TOKEN-1'" "$OUT"
run_ct $NOW0 --env npm
assert_eq "--env npm - exact line" "export AWS_CODEARTIFACT_TOKEN='FAKE-TOKEN-1'" "$OUT"
run_ct $NOW0 --print
assert_eq "--print - bare token" "FAKE-TOKEN-1" "$OUT"
assert_eq "output modes - one fetch served all three" 1 "$(calls)"
# the eval round trip must survive a single quote inside the token
new_case c5q
FAKE_TOKEN="FAKE'QUOTE-TOKEN" run_ct $NOW0 --env npm
unset AWS_CODEARTIFACT_TOKEN
eval "$OUT"
assert_eq "--env npm - eval round-trips a token with a single quote" "FAKE'QUOTE-TOKEN" "${AWS_CODEARTIFACT_TOKEN:-}"
unset AWS_CODEARTIFACT_TOKEN

# ---- 6. --check ---------------------------------------------------------------------
new_case c6
run_ct $NOW0 --check
assert_eq "--check - cold cache exits 1" 1 "$RC"
assert_eq "--check - cold cache prints nothing" "" "$OUT$ERR"
run_ct $NOW0
run_ct $((NOW0 + H)) --check
assert_eq "--check - valid cache exits 0" 0 "$RC"
assert_eq "--check - valid cache prints nothing" "" "$OUT$ERR"
run_ct $((NOW0 + 11 * H + 1)) --check
assert_eq "--check - expired cache exits 1" 1 "$RC"
assert_eq "--check - never calls aws" 1 "$(calls)"

# ---- 7. short-lived token: valid until expiration - 30 min ---------------------------
new_case c7
FAKE_EXP_ISO=$(iso_of $((NOW0 + 2 * H))) run_ct $NOW0
FAKE_EXP_ISO=$(iso_of $((NOW0 + 2 * H))) run_ct $((NOW0 + 2 * H - 1800 - 1)) --check
assert_eq "short expiry - still valid just before exp-30m" 0 "$RC"
run_ct $((NOW0 + 2 * H - 1800)) --check
assert_eq "short expiry - invalid at exp-30m" 1 "$RC"
# a token that is already inside the margin is an error, not a cached success
new_case c7b
FAKE_EXP_ISO=$(iso_of $((NOW0 + 600))) run_ct $NOW0
assert_eq "near-expired response - exit 4" 4 "$RC"
assert_eq "near-expired response - nothing cached" 0 "$(ls "$CACHE" 2>/dev/null | wc -l | tr -d ' ')"

# ---- 8. failure: expired SSO ---------------------------------------------------------
new_case c8
FAKE_FAIL_MSG="The SSO session associated with this profile has expired or is otherwise invalid." run_ct $NOW0 --env gradle
assert_eq "aws expired - exit 4" 4 "$RC"
assert_eq "aws expired - nothing on stdout" "" "$OUT"
assert_err_has "aws expired - exact login command" "aws sso login --profile fb-common-non-prod/Repository-ReadOnly"
assert_err_has "aws expired - aws message relayed" "has expired"
assert_err_lacks "aws expired - no token text" "FAKE-TOKEN"
FAKE_FAIL_MSG="Unable to locate credentials" run_ct $NOW0 --profile fb-other-111111111111/Test
assert_err_has "aws failure - login command uses the chosen profile" "aws sso login --profile fb-other-111111111111/Test"
assert_eq "aws failure - exit 4" 4 "$RC"
assert_eq "aws failure - failed fetch caches nothing" 0 "$(ls "$CACHE" 2>/dev/null | wc -l | tr -d ' ')"

# garbage JSON must not be echoed back (it could hold a token)
FAKE_RAW='{"secret":"LEAK-ME-111111111111"}' run_ct $NOW0
assert_eq "bad response - exit 4" 4 "$RC"
assert_err_lacks "bad response - body never echoed" "LEAK-ME"
assert_out_lacks "bad response - body never on stdout" "LEAK-ME"

# ---- 9. a failed fetch never falls back to a stale cache -----------------------------
new_case c9
run_ct $NOW0
FAKE_FAIL_MSG="Token has expired" run_ct $((NOW0 + 11 * H + 1)) --env gradle
assert_eq "stale cache - exit 4 after expiry" 4 "$RC"
assert_out_lacks "stale cache - old token not printed (stdout)" "FAKE-TOKEN-1"
assert_err_lacks "stale cache - old token not printed (stderr)" "FAKE-TOKEN-1"
assert_err_has "stale cache - login hint printed" "aws sso login --profile"
FAKE_FAIL_MSG="Token has expired" run_ct $((NOW0 + H)) --refresh --print
assert_eq "--refresh with failing aws - exit 4 even though cache is valid" 4 "$RC"
assert_out_lacks "--refresh with failing aws - cached token not served" "FAKE-TOKEN-1"

# ---- 10. config: env overrides, flags win, cache keyed per profile --------------------
new_case c10
CA_TOKEN_PROFILE=env-profile CA_TOKEN_DOMAIN=envdomain CA_TOKEN_OWNER=111111111111 CA_TOKEN_REGION=eu-west-1 run_ct $NOW0
assert_eq "env overrides - argv" \
  "codeartifact get-authorization-token --profile env-profile --domain envdomain --domain-owner 111111111111 --region eu-west-1 --output json" \
  "$(head -1 "$ARGV_LOG")"
CA_TOKEN_PROFILE=env-profile run_ct $NOW0 --profile flag-profile --domain flagdomain --domain-owner 222222222222 --region ap-south-1
assert_eq "flags beat env - argv" \
  "codeartifact get-authorization-token --profile flag-profile --domain flagdomain --domain-owner 222222222222 --region ap-south-1 --output json" \
  "$(sed -n 2p "$ARGV_LOG")"
assert_eq "cache keyed by profile|domain|owner - two files" 2 "$(ls "$CACHE" | wc -l | tr -d ' ')"
# the region is part of the key: same profile/domain/owner, another region = another token
new_case c10b
FAKE_TOKEN=TOKEN-USW2 run_ct $NOW0 --region us-west-2 --env npm
FAKE_TOKEN=TOKEN-EUW1 run_ct $NOW0 --region eu-west-1 --env npm
assert_eq "cache keyed by region - second region fetches, not reuses" 2 "$(calls)"
assert_eq "cache keyed by region - second region gets its own token" "export AWS_CODEARTIFACT_TOKEN='TOKEN-EUW1'" "$OUT"
assert_eq "cache keyed by region - two files" 2 "$(ls "$CACHE" | wc -l | tr -d ' ')"
FAKE_TOKEN=TOKEN-NEVER run_ct $NOW0 --region us-west-2 --env npm
assert_eq "cache keyed by region - first region still served from its own file" "export AWS_CODEARTIFACT_TOKEN='TOKEN-USW2'" "$OUT"
assert_eq "cache keyed by region - no extra fetch" 2 "$(calls)"
run_ct $NOW0 --check --region ap-south-1
assert_eq "cache keyed by region - --check for an unseen region is a miss" 1 "$RC"
# with CA_TOKEN_CACHE_DIR empty the XDG location is used, in a claude-bin dir
CACHE="" XDG_CACHE_HOME="$WORK/xdg" run_ct $NOW0
assert_eq "XDG_CACHE_HOME - cache under claude-bin" 1 "$(ls "$WORK/xdg/claude-bin" 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "XDG_CACHE_HOME - dir mode 700" 700 "$(mode_of "$WORK/xdg/claude-bin")"

# ---- 11. usage and missing aws -------------------------------------------------------
new_case c11
run_ct $NOW0 --bogus
assert_eq "unknown flag - exit 3" 3 "$RC"
run_ct $NOW0 --env pip
assert_eq "bad --env value - exit 3" 3 "$RC"
run_ct $NOW0 --env gradle --print
assert_eq "--env with --print - exit 3" 3 "$RC"
run_ct $NOW0 --profile
assert_eq "missing flag value - exit 3" 3 "$RC"
CT_AWS="$WORK/no-such-aws" run_ct $NOW0
assert_eq "missing aws - exit 3" 3 "$RC"
OUT=$("$CT" --help 2>&1); RC=$?
assert_eq "help - exit 0" 0 "$RC"
assert_out_has "help - prints header usage" "ca-token [--env gradle|npm] [--print]"
assert_out_lacks "help - stops at end of header" "set -uo pipefail"

echo
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
