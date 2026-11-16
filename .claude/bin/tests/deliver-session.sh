#!/bin/bash
#
# Tests for deliver-session. A fake tmux (TMUX_BIN) records every call's argv as
# [arg][arg]... on one line and answers has-session from FAKE_HAS_SESSION; the git
# root is a temp dir (DELIVER_SESSION_GIT_ROOT) with throwaway repos. No real tmux
# session and no real claude is ever started. Every name here is synthetic.
#
# Usage: bin/tests/deliver-session.sh        (exit 1 if any case fails)

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
DS="$HERE/../deliver-session"
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
OUT=""; ERR=""; RC=0

ok()  { PASS=$((PASS + 1)); echo "PASS  $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL  $1"; echo "      $2"; echo "      stdout: $OUT" | head -5; echo "      stderr: $ERR" | head -5; }

assert_eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi; }
assert_out_has()   { if printf '%s\n' "$OUT" | grep -qF -- "$2"; then ok "$1"; else bad "$1" "stdout missing: $2"; fi; }
assert_out_lacks() { if printf '%s\n' "$OUT" | grep -qF -- "$2"; then bad "$1" "stdout unexpectedly has: $2"; else ok "$1"; fi; }
assert_err_has()   { if printf '%s\n' "$ERR" | grep -qF -- "$2"; then ok "$1"; else bad "$1" "stderr missing: $2"; fi; }

# calls SUBCOMMAND : how many times the fake tmux was run with that subcommand.
calls() {
  if [ -f "$ARGV_LOG" ]; then grep -c -F -- "[$1]" "$ARGV_LOG" | head -1; else echo 0; fi
}
# line_of SUBCOMMAND : the first logged line for that subcommand ("" if none).
line_of() {
  if [ -f "$ARGV_LOG" ]; then grep -F -- "[$1]" "$ARGV_LOG" | head -1; fi
}
total_calls() { if [ -f "$ARGV_LOG" ]; then wc -l < "$ARGV_LOG" | tr -d ' '; else echo 0; fi; }

GIT_ROOT="$WORK/git"
mkdir -p "$GIT_ROOT"
git init -q "$GIT_ROOT/myrepo" || { echo "cannot create test repo"; exit 1; }
mkdir -p "$GIT_ROOT/plain"                 # not a git work tree
mkdir -p "$GIT_ROOT/myrepo/sub"            # plain dir inside another work tree
mkdir -p "$WORK/home/git"
git init -q "$WORK/home/git/homerepo" || exit 1

# Fake tmux. FAKE_HAS_SESSION=1 makes has-session succeed; FAKE_NEW_RC makes
# new-session exit with that status.
FAKE_TMUX="$WORK/fake-tmux"
cat > "$FAKE_TMUX" <<'EOF'
#!/bin/bash
{ printf '[%s]' "$@"; echo; } >> "$FAKE_ARGV_LOG"
case "$1" in
  has-session) [ "${FAKE_HAS_SESSION:-0}" = "1" ] && exit 0; exit 1 ;;
  new-session) exit "${FAKE_NEW_RC:-0}" ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$FAKE_TMUX"

# run_ds [args...] : stdout -> OUT, stderr -> ERR, exit -> RC. Fake behaviour is
# set through the caller's prefix assignments.
run_ds() {
  local errf="$WORK/stderr.txt"
  OUT=$(DELIVER_SESSION_GIT_ROOT="${DS_ROOT:-$GIT_ROOT}" TMUX_BIN="${DS_TMUX:-$FAKE_TMUX}" FAKE_ARGV_LOG="$ARGV_LOG" \
        "$DS" "$@" 2>"$errf" < /dev/null)
  RC=$?
  ERR=$(cat "$errf")
}

new_case() { ARGV_LOG="$WORK/tmux-$1.argv"; rm -f "$ARGV_LOG"; }

unset TMUX CLAUDE_BIN DELIVER_SESSION_GIT_ROOT TMUX_BIN

# shellcheck disable=SC2016  # literal text compared against the logged argv
BASHC='claude_bin="$1"; shift; "$claude_bin" "$@"; exec bash -l'
URL1="https://fullbay.atlassian.net/browse/HUB-841"
NEW_HUB="[new-session][-d][-s][HUB-841][-c][$GIT_ROOT/myrepo][--][bash][-lc][$BASHC][_][claude][--model][opus][--permission-mode][plan][-n][HUB-841][/deliver $URL1]"

# ---- 1. bare key and URL forms give the same session ---------------------------------
new_case k1
run_ds myrepo HUB-841 --detach
assert_eq "bare key - exit 0" 0 "$RC"
assert_eq "bare key - exact new-session argv" "$NEW_HUB" "$(line_of new-session)"
assert_eq "bare key - existing-session check uses the exact-match target" "[has-session][-t][=HUB-841]" "$(line_of has-session)"
assert_eq "bare key - exactly one new-session" 1 "$(calls new-session)"

for form in \
  "https://fullbay.atlassian.net/browse/HUB-841" \
  "https://fullbay.atlassian.net/browse/HUB-841/" \
  "https://fullbay.atlassian.net/browse/HUB-841?focusedCommentId=1" \
  "https://fullbay.atlassian.net/browse/HUB-841#comment" \
  "https://fullbay.atlassian.net/browse/HUB-841/?a=b#c" \
  "https://other.example.test/browse/HUB-841"; do
  new_case k2
  run_ds myrepo "$form" -d
  assert_eq "ticket form [$form] - exit 0" 0 "$RC"
  assert_eq "ticket form [$form] - same argv as the bare key" "$NEW_HUB" "$(line_of new-session)"
done

new_case k3
run_ds myrepo AB2C-17 -d
assert_eq "alphanumeric project key - canonical url" \
  "/deliver https://fullbay.atlassian.net/browse/AB2C-17" \
  "$(line_of new-session | sed 's/.*\[\(\/deliver [^]]*\)\]$/\1/')"

# ---- 2. bad tickets exit 1 before any tmux call --------------------------------------
for t in "hub-841" "HUB841" "HUB-" "H-1" "1UB-5" "HUB-841x" "HUB-841 x" \
         "https://fullbay.atlassian.net/jira/HUB-841" "https://fullbay.atlassian.net/browse/" \
         "https://fullbay.atlassian.net/browse/hub-841" "HUB-841/" "ftp:" ""; do
  new_case bt
  run_ds myrepo "$t"
  assert_eq "bad ticket [$t] - exit 1" 1 "$RC"
  assert_eq "bad ticket [$t] - no tmux call" 0 "$(total_calls)"
done
assert_err_has "bad ticket - message names the ticket" "not a Jira key"

# ---- 3. bad repos exit 1 --------------------------------------------------------------
new_case r1
run_ds nope HUB-841
assert_eq "missing repo - exit 1" 1 "$RC"
assert_err_has "missing repo - message" "repo not found"
run_ds plain HUB-841
assert_eq "non-git dir - exit 1" 1 "$RC"
assert_err_has "non-git dir - message" "not a git work tree"
DS_ROOT="$GIT_ROOT/myrepo" run_ds sub HUB-841
assert_eq "plain dir inside another work tree - exit 1" 1 "$RC"
run_ds "myrepo/sub" HUB-841
assert_eq "repo containing / - exit 1" 1 "$RC"
run_ds "$GIT_ROOT/myrepo" HUB-841
assert_eq "absolute repo path - exit 1" 1 "$RC"
run_ds ".." HUB-841
assert_eq "repo .. - exit 1" 1 "$RC"
run_ds "" HUB-841
assert_eq "empty repo - exit 1" 1 "$RC"
assert_eq "bad repos - no tmux call" 0 "$(total_calls)"

# ---- 4. default git root is ~/git ------------------------------------------------------
new_case h1
OUT=$(env -u DELIVER_SESSION_GIT_ROOT HOME="$WORK/home" TMUX_BIN="$FAKE_TMUX" FAKE_ARGV_LOG="$ARGV_LOG" "$DS" homerepo HUB-841 -d 2>&1 < /dev/null); RC=$?
assert_eq "default root - exit 0" 0 "$RC"
assert_eq "default root - -c is \$HOME/git/<repo>" "$WORK/home/git/homerepo" \
  "$(line_of new-session | sed 's/.*\[-c\]\[\([^]]*\)\].*/\1/')"

# ---- 5. attach vs switch-client ---------------------------------------------------------
new_case a1
run_ds myrepo HUB-841
assert_eq "outside tmux - exit 0" 0 "$RC"
assert_eq "outside tmux - attach-session on the exact target" "[attach-session][-t][=HUB-841]" "$(line_of attach-session)"
assert_eq "outside tmux - no switch-client" 0 "$(calls switch-client)"
assert_eq "outside tmux - session created first" 1 "$(calls new-session)"

new_case a2
TMUX="/tmp/fake-tmux-socket,1,0" run_ds myrepo HUB-841
assert_eq "inside tmux - exit 0" 0 "$RC"
assert_eq "inside tmux - switch-client on the exact target" "[switch-client][-t][=HUB-841]" "$(line_of switch-client)"
assert_eq "inside tmux - no attach-session" 0 "$(calls attach-session)"
assert_eq "inside tmux - session created" 1 "$(calls new-session)"

# ---- 6. --detach and option placement ------------------------------------------------------
new_case d1
run_ds myrepo HUB-841 --detach
assert_eq "--detach after positionals - no attach" 0 "$(calls attach-session)"
assert_eq "--detach - no switch-client" 0 "$(calls switch-client)"
assert_eq "--detach - session still created" 1 "$(calls new-session)"
new_case d2
TMUX="/tmp/fake-tmux-socket,1,0" run_ds -d myrepo HUB-841
assert_eq "-d before positionals inside tmux - no switch-client" 0 "$(calls switch-client)"
assert_eq "-d before positionals - session created" 1 "$(calls new-session)"
new_case d3
run_ds myrepo --detach HUB-841
assert_eq "--detach between positionals - exit 0" 0 "$RC"
assert_eq "--detach between positionals - no attach" 0 "$(calls attach-session)"
new_case d4
run_ds -- myrepo HUB-841 -d
assert_eq "after -- everything is positional - -d is a third arg, exit 3" 3 "$RC"

# ---- 7. existing session ----------------------------------------------------------------------
new_case e1
FAKE_HAS_SESSION=1 run_ds myrepo HUB-841
assert_eq "existing session - exit 0" 0 "$RC"
assert_eq "existing session - no new-session" 0 "$(calls new-session)"
assert_eq "existing session - attaches" "[attach-session][-t][=HUB-841]" "$(line_of attach-session)"
assert_err_has "existing session - message" "deliver-session: session HUB-841 already exists, attaching"

new_case e2
TMUX="/tmp/fake-tmux-socket,1,0" FAKE_HAS_SESSION=1 run_ds myrepo HUB-841
assert_eq "existing session inside tmux - switch-client" "[switch-client][-t][=HUB-841]" "$(line_of switch-client)"
assert_eq "existing session inside tmux - no new-session" 0 "$(calls new-session)"

new_case e3
FAKE_HAS_SESSION=1 run_ds myrepo HUB-841 --detach
assert_eq "existing session with --detach - exit 0" 0 "$RC"
assert_eq "existing session with --detach - no new-session" 0 "$(calls new-session)"
assert_eq "existing session with --detach - no attach" 0 "$(calls attach-session)"
assert_eq "existing session with --detach - no switch-client" 0 "$(calls switch-client)"

# ---- 8. --dry-run -------------------------------------------------------------------------------
new_case n1
run_ds myrepo "$URL1" --dry-run
assert_eq "--dry-run - exit 0" 0 "$RC"
assert_eq "--dry-run - only has-session ran" "[has-session][-t][=HUB-841]" "$(cat "$ARGV_LOG")"
assert_out_has "--dry-run - prints new-session" "new-session"
assert_out_has "--dry-run - prints the session name" "-s HUB-841"
assert_out_has "--dry-run - prints the quoted /deliver argument" '/deliver\ https://fullbay.atlassian.net/browse/HUB-841'
# the printed line must round-trip through the shell to the exact argv
eval "DRY_ARGV=($OUT)"
assert_eq "--dry-run - round-trips: tmux binary" "$FAKE_TMUX" "${DRY_ARGV[0]}"
assert_eq "--dry-run - round-trips: pane script is one argument" "$BASHC" "${DRY_ARGV[10]}"
assert_eq "--dry-run - round-trips: last argument" "/deliver $URL1" "${DRY_ARGV[${#DRY_ARGV[@]}-1]}"
assert_eq "--dry-run - round-trips: argument count" 20 "${#DRY_ARGV[@]}"

new_case n2
TMUX="/tmp/fake-tmux-socket,1,0" FAKE_HAS_SESSION=1 run_ds --dry-run myrepo HUB-841
assert_eq "--dry-run with existing session - exit 0" 0 "$RC"
assert_eq "--dry-run with existing session - only has-session ran" "[has-session][-t][=HUB-841]" "$(cat "$ARGV_LOG")"

# ---- 9. CLAUDE_BIN is an argument, never shell text -----------------------------------------------
new_case c1
CLAUDE_BIN="/opt/my claude/bin/cl'aude" run_ds myrepo HUB-841 --dry-run
eval "DRY_ARGV=($OUT)"
assert_eq "CLAUDE_BIN with space and quote - arrives as one argument" "/opt/my claude/bin/cl'aude" "${DRY_ARGV[12]}"
assert_eq "CLAUDE_BIN - pane script is unchanged" "$BASHC" "${DRY_ARGV[10]}"
new_case c2
CLAUDE_BIN="/opt/claude-x" run_ds myrepo HUB-841 --detach
assert_eq "CLAUDE_BIN override - in the new-session argv" \
  "[new-session][-d][-s][HUB-841][-c][$GIT_ROOT/myrepo][--][bash][-lc][$BASHC][_][/opt/claude-x][--model][opus][--permission-mode][plan][-n][HUB-841][/deliver $URL1]" \
  "$(line_of new-session)"

# ---- 10. failures are loud --------------------------------------------------------------------------
new_case f1
FAKE_NEW_RC=1 run_ds myrepo HUB-841
assert_eq "new-session failure - exit 4" 4 "$RC"
assert_err_has "new-session failure - message" "new-session for HUB-841 failed"
assert_eq "new-session failure - no attach" 0 "$(calls attach-session)"
new_case f2
DS_TMUX="$WORK/no-such-tmux" run_ds myrepo HUB-841
assert_eq "missing tmux - exit 3" 3 "$RC"
assert_err_has "missing tmux - message" "tmux not found"

# ---- 11. usage ---------------------------------------------------------------------------------------
new_case u1
run_ds
assert_eq "no arguments - exit 3" 3 "$RC"
run_ds myrepo
assert_eq "one positional - exit 3" 3 "$RC"
run_ds myrepo HUB-841 extra
assert_eq "three positionals - exit 3" 3 "$RC"
run_ds myrepo HUB-841 --bogus
assert_eq "unknown option - exit 3" 3 "$RC"
assert_eq "usage errors - no tmux call" 0 "$(total_calls)"
OUT=$("$DS" --help 2>&1); RC=$?
assert_eq "help - exit 0" 0 "$RC"
assert_out_has "help - prints header usage" "deliver-session <repo> <ticket>"
assert_out_lacks "help - stops at end of header" "set -uo pipefail"
OUT=$("$DS" myrepo -h 2>&1); RC=$?
assert_eq "-h after a positional - exit 0" 0 "$RC"

echo
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
