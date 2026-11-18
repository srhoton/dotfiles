#!/bin/bash
#
# Tests for deliver-session. A fake tmux (TMUX_BIN) records every call's argv as
# [arg][arg]... on one line and answers has-session, list-panes and split-window
# from FAKE_* env vars (see the fake below); a fake rex (REX_BIN) does the same for
# ls, block ls, split, new, focus and do. The git
# root is a temp dir (DELIVER_SESSION_GIT_ROOT) with throwaway repos. No real tmux
# or rex session and no real claude is ever started. Every name here is synthetic.
# REX_SESSION, REX_BLOCK and REX_CLIENT are unset below, because the suite may run
# inside a Rex pane; only the Rex cases set them, as prefix assignments to run_ds.
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
# rcalls SUBCOMMAND / rline_of SUBCOMMAND / rtotal : the same for the fake rex's log.
rcalls() {
  if [ -f "$REX_LOG" ]; then grep -c -F -- "[$1]" "$REX_LOG" | head -1; else echo 0; fi
}
rline_of() {
  if [ -f "$REX_LOG" ]; then grep -F -- "[$1]" "$REX_LOG" | head -1; fi
}
rtotal() { if [ -f "$REX_LOG" ]; then wc -l < "$REX_LOG" | tr -d ' '; else echo 0; fi; }
# rorder : the fake rex's subcommands in call order, space separated.
rorder() { sed 's/^\[\([^]]*\)\].*/\1/' "$REX_LOG" | tr '\n' ' ' | sed 's/ $//'; }

GIT_ROOT="$WORK/git"
mkdir -p "$GIT_ROOT"
git init -q "$GIT_ROOT/myrepo" || { echo "cannot create test repo"; exit 1; }
mkdir -p "$GIT_ROOT/plain"                 # not a git work tree
mkdir -p "$GIT_ROOT/myrepo/sub"            # plain dir inside another work tree
mkdir -p "$WORK/home/git"
git init -q "$WORK/home/git/homerepo" || exit 1

# Fake tmux. FAKE_HAS_SESSION=1 makes has-session succeed; FAKE_NEW_RC makes
# new-session exit with that status. FAKE_LIST_PANES is printed verbatim by
# list-panes (FAKE_LIST_RC is its exit status); FAKE_SPLIT_OUT is what split-window
# prints as the new pane id (default %42, set-but-empty prints nothing) and
# FAKE_SPLIT_RC is its exit status.
FAKE_TMUX="$WORK/fake-tmux"
cat > "$FAKE_TMUX" <<'EOF'
#!/bin/bash
{ printf '[%s]' "$@"; echo; } >> "$FAKE_ARGV_LOG"
case "$1" in
  has-session) [ "${FAKE_HAS_SESSION:-0}" = "1" ] && exit 0; exit 1 ;;
  new-session) exit "${FAKE_NEW_RC:-0}" ;;
  list-panes)
    [ -n "${FAKE_LIST_PANES:-}" ] && printf '%s\n' "$FAKE_LIST_PANES"
    exit "${FAKE_LIST_RC:-0}" ;;
  split-window)
    [ -n "${FAKE_SPLIT_OUT-%42}" ] && printf '%s\n' "${FAKE_SPLIT_OUT-%42}"
    exit "${FAKE_SPLIT_RC:-0}" ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$FAKE_TMUX"

# Fake rex (REX_BIN). Records argv like the fake tmux, to FAKE_REX_LOG. Answers the
# subcommands deliver-session uses with canned JSON:
#   ls                FAKE_REX_LS         (default: one session, session:cur)
#   block ls -s S     FAKE_REX_BLOCKS     (default: no blocks); when FAKE_REX_BLOCKS_SESSION
#                     is set, only that session has them, every other one has none
#   split             FAKE_REX_SPLIT_OUT  (default: {"block_ids":["block:new1"]}; set-but-empty
#                     prints nothing)
#   new               FAKE_REX_NEW_OUT    (default: {"session_id":"session:new1"})
# FAKE_REX_RC is the exit status: of every subcommand, or only of the one named by
# FAKE_REX_FAIL_ON (ls, block, split, new, focus, do) when that is set.
FAKE_REX="$WORK/fake-rex"
cat > "$FAKE_REX" <<'EOF'
#!/bin/bash
{ printf '[%s]' "$@"; echo; } >> "$FAKE_REX_LOG"
args=("$@")
if [ "${1:-}" = "-C" ]; then shift 2; fi
sub="${1:-}"
if [ "${FAKE_REX_RC:-0}" != "0" ] && { [ -z "${FAKE_REX_FAIL_ON:-}" ] || [ "$FAKE_REX_FAIL_ON" = "$sub" ]; }; then
  echo "fake rex: $sub failed" >&2
  exit "$FAKE_REX_RC"
fi
no_blocks='{"blocks":[]}'
def_ls='{"sessions":[{"session_id":"session:cur","label":"main"}]}'
def_split='{"block_ids":["block:new1"]}'
def_new='{"session_id":"session:new1"}'
case "$sub" in
  ls) printf '%s\n' "${FAKE_REX_LS-$def_ls}" ;;
  block)
    sid=""
    for ((i = 0; i < ${#args[@]}; i++)); do [ "${args[$i]}" = "-s" ] && sid="${args[$((i + 1))]}"; done
    if [ -n "${FAKE_REX_BLOCKS_SESSION:-}" ] && [ "$sid" != "$FAKE_REX_BLOCKS_SESSION" ]; then
      printf '%s\n' "$no_blocks"
    else
      printf '%s\n' "${FAKE_REX_BLOCKS-$no_blocks}"
    fi ;;
  split) out="${FAKE_REX_SPLIT_OUT-$def_split}"; [ -n "$out" ] && printf '%s\n' "$out"; exit 0 ;;
  new) out="${FAKE_REX_NEW_OUT-$def_new}"; [ -n "$out" ] && printf '%s\n' "$out"; exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$FAKE_REX"

# run_ds [args...] : stdout -> OUT, stderr -> ERR, exit -> RC. Fake behaviour is
# set through the caller's prefix assignments (TMUX, REX_SESSION, FAKE_* ...).
run_ds() {
  local errf="$WORK/stderr.txt"
  OUT=$(DELIVER_SESSION_GIT_ROOT="${DS_ROOT:-$GIT_ROOT}" TMUX_BIN="${DS_TMUX:-$FAKE_TMUX}" REX_BIN="${DS_REX:-$FAKE_REX}" \
        FAKE_ARGV_LOG="$ARGV_LOG" FAKE_REX_LOG="$REX_LOG" \
        "$DS" "$@" 2>"$errf" < /dev/null)
  RC=$?
  ERR=$(cat "$errf")
}

new_case() { ARGV_LOG="$WORK/tmux-$1.argv"; REX_LOG="$WORK/rex-$1.argv"; rm -f "$ARGV_LOG" "$REX_LOG"; }

# The suite may itself be running inside Rex (REX_SESSION set) or tmux: strip every
# variable that selects a multiplexer, so only a case that sets one gets it.
unset TMUX CLAUDE_BIN DELIVER_SESSION_GIT_ROOT TMUX_BIN REX_BIN REX_SESSION REX_BLOCK REX_CLIENT

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
TMUX="/tmp/fake-tmux-socket,1,0" run_ds myrepo HUB-841 --new-session
assert_eq "inside tmux --new-session - exit 0" 0 "$RC"
assert_eq "inside tmux --new-session - switch-client on the exact target" "[switch-client][-t][=HUB-841]" "$(line_of switch-client)"
assert_eq "inside tmux --new-session - no attach-session" 0 "$(calls attach-session)"
assert_eq "inside tmux --new-session - session created" 1 "$(calls new-session)"
assert_eq "inside tmux --new-session - no pane split" 0 "$(calls split-window)"
assert_eq "inside tmux --new-session - exact new-session argv" "$NEW_HUB" "$(line_of new-session)"
assert_eq "inside tmux --new-session - no pane lookup" 0 "$(calls list-panes)"

# ---- 6. --detach and option placement ------------------------------------------------------
new_case d1
run_ds myrepo HUB-841 --detach
assert_eq "--detach after positionals - no attach" 0 "$(calls attach-session)"
assert_eq "--detach - no switch-client" 0 "$(calls switch-client)"
assert_eq "--detach - session still created" 1 "$(calls new-session)"
new_case d2
TMUX="/tmp/fake-tmux-socket,1,0" run_ds -d myrepo HUB-841 --new-session
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
TMUX="/tmp/fake-tmux-socket,1,0" FAKE_HAS_SESSION=1 run_ds --dry-run --new-session myrepo HUB-841
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

# ---- 11. pane mode ($TMUX set, no --new-session) --------------------------------------------------------
INSIDE="/tmp/fake-tmux-socket,1,0"
SPLIT_HEAD="[split-window][-h]"
SPLIT_TAIL="[-P][-F][#{pane_id}][-c][$GIT_ROOT/myrepo][--][bash][-lc][$BASHC][_][claude][--model][opus][--permission-mode][plan][-n][HUB-841][/deliver $URL1]"

new_case p1
TMUX="$INSIDE" run_ds myrepo HUB-841
assert_eq "pane mode - exit 0" 0 "$RC"
assert_eq "pane mode - exact split-window argv" "$SPLIT_HEAD$SPLIT_TAIL" "$(line_of split-window)"
assert_eq "pane mode - exactly one split-window" 1 "$(calls split-window)"
assert_eq "pane mode - no new-session" 0 "$(calls new-session)"
assert_eq "pane mode - no attach-session" 0 "$(calls attach-session)"
assert_eq "pane mode - no switch-client" 0 "$(calls switch-client)"
assert_eq "pane mode - pane lookup is across all sessions" "[list-panes][-a][-F][#{pane_id} #{@deliver_ticket}]" "$(line_of list-panes)"
assert_eq "pane mode - tags the new pane" "[set-option][-p][-t][%42][@deliver_ticket][HUB-841]" "$(line_of set-option)"
assert_eq "pane mode - titles the new pane" "[select-pane][-t][%42][-T][HUB-841]" "$(line_of select-pane)"
assert_eq "pane mode - session is not renamed" 0 "$(calls rename-session)"
assert_err_has "pane mode - reports the pane" "deliver-session: started HUB-841 in pane %42"
assert_eq "pane mode - call order" "list-panes has-session split-window set-option select-pane" \
  "$(sed 's/^\[\([^]]*\)\].*/\1/' "$ARGV_LOG" | tr '\n' ' ' | sed 's/ $//')"

new_case p2
TMUX="$INSIDE" run_ds myrepo HUB-841 --detach
assert_eq "pane mode --detach - exit 0" 0 "$RC"
assert_eq "pane mode --detach - split-window gets -d" "${SPLIT_HEAD}[-d]${SPLIT_TAIL}" "$(line_of split-window)"
assert_eq "pane mode --detach - still tags the pane" "[set-option][-p][-t][%42][@deliver_ticket][HUB-841]" "$(line_of set-option)"
assert_eq "pane mode --detach - no switch-client" 0 "$(calls switch-client)"

new_case p3
TMUX="$INSIDE" FAKE_LIST_PANES=$'%3 \n%7 HUB-999\n%9 HUB-841' run_ds myrepo HUB-841
assert_eq "existing pane - exit 0" 0 "$RC"
assert_eq "existing pane - no split-window" 0 "$(calls split-window)"
assert_eq "existing pane - no new-session" 0 "$(calls new-session)"
assert_eq "existing pane - no set-option" 0 "$(calls set-option)"
assert_err_has "existing pane - message" "deliver-session: pane %9 already running HUB-841, selecting it"
assert_eq "existing pane - switch-client" "[switch-client][-t][%9]" "$(line_of switch-client)"
assert_eq "existing pane - select-window" "[select-window][-t][%9]" "$(line_of select-window)"
assert_eq "existing pane - select-pane" "[select-pane][-t][%9]" "$(line_of select-pane)"
assert_eq "existing pane - focus order" "switch-client select-window select-pane" \
  "$(sed 's/^\[\([^]]*\)\].*/\1/' "$ARGV_LOG" | grep -v '^list-panes$' | tr '\n' ' ' | sed 's/ $//')"

new_case p4
TMUX="$INSIDE" FAKE_LIST_PANES=$'%9 HUB-841' run_ds myrepo HUB-841 --detach
assert_eq "existing pane --detach - exit 0" 0 "$RC"
assert_err_has "existing pane --detach - message" "already running HUB-841, not selecting (--detach)"
assert_eq "existing pane --detach - no split-window" 0 "$(calls split-window)"
assert_eq "existing pane --detach - no switch-client" 0 "$(calls switch-client)"
assert_eq "existing pane --detach - no select-window" 0 "$(calls select-window)"
assert_eq "existing pane --detach - no select-pane" 0 "$(calls select-pane)"

new_case p5
TMUX="$INSIDE" FAKE_LIST_PANES=$'%7 HUB-8410\n%8 HUB-84\n%9 XHUB-841' run_ds myrepo HUB-841
assert_eq "other tickets' panes are not a match - split-window ran" 1 "$(calls split-window)"

new_case p6
TMUX="$INSIDE" FAKE_HAS_SESSION=1 run_ds myrepo HUB-841
assert_eq "pane mode with existing session - exit 0" 0 "$RC"
assert_eq "pane mode with existing session - switch-client" "[switch-client][-t][=HUB-841]" "$(line_of switch-client)"
assert_eq "pane mode with existing session - no split-window" 0 "$(calls split-window)"
assert_eq "pane mode with existing session - no new-session" 0 "$(calls new-session)"
assert_err_has "pane mode with existing session - message" "session HUB-841 already exists, attaching"

new_case p7
TMUX="$INSIDE" FAKE_HAS_SESSION=1 FAKE_LIST_PANES=$'%9 HUB-841' run_ds myrepo HUB-841
assert_eq "pane and session both exist - the pane wins" "[switch-client][-t][%9]" "$(line_of switch-client)"
assert_eq "pane and session both exist - session is not consulted" 0 "$(calls has-session)"

new_case p8
TMUX="$INSIDE" run_ds myrepo HUB-841 --dry-run
assert_eq "pane mode --dry-run - exit 0" 0 "$RC"
assert_eq "pane mode --dry-run - only list-panes and has-session ran" \
  "[list-panes][-a][-F][#{pane_id} #{@deliver_ticket}]
[has-session][-t][=HUB-841]" "$(cat "$ARGV_LOG")"
assert_out_has "pane mode --dry-run - prints split-window" "split-window -h -P -F"
eval "DRY_ARGV=($OUT)"
assert_eq "pane mode --dry-run - round-trips: tmux binary" "$FAKE_TMUX" "${DRY_ARGV[0]}"
assert_eq "pane mode --dry-run - round-trips: -F format is one argument" "#{pane_id}" "${DRY_ARGV[5]}"
assert_eq "pane mode --dry-run - round-trips: pane script is one argument" "$BASHC" "${DRY_ARGV[11]}"
assert_eq "pane mode --dry-run - round-trips: last argument" "/deliver $URL1" "${DRY_ARGV[${#DRY_ARGV[@]}-1]}"
assert_eq "pane mode --dry-run - round-trips: argument count" 21 "${#DRY_ARGV[@]}"
new_case p8b
TMUX="$INSIDE" run_ds myrepo HUB-841 --dry-run -d
eval "DRY_ARGV=($OUT)"
assert_eq "pane mode --dry-run --detach - prints -d" "-d" "${DRY_ARGV[3]}"
new_case p8c
CLAUDE_BIN="/opt/my claude/bin/cl'aude" TMUX="$INSIDE" run_ds myrepo HUB-841 --dry-run
eval "DRY_ARGV=($OUT)"
assert_eq "pane mode --dry-run - CLAUDE_BIN arrives as one argument" "/opt/my claude/bin/cl'aude" "${DRY_ARGV[13]}"
new_case p8d
TMUX="$INSIDE" FAKE_LIST_PANES=$'%9 HUB-841' run_ds myrepo HUB-841 --dry-run
assert_eq "pane mode --dry-run with existing pane - exit 0" 0 "$RC"
assert_eq "pane mode --dry-run with existing pane - only list-panes ran" "[list-panes][-a][-F][#{pane_id} #{@deliver_ticket}]" "$(cat "$ARGV_LOG")"

new_case p9
TMUX="$INSIDE" FAKE_SPLIT_RC=1 run_ds myrepo HUB-841
assert_eq "split-window failure - exit 4" 4 "$RC"
assert_err_has "split-window failure - message" "split-window for HUB-841 failed"
assert_eq "split-window failure - pane is not tagged" 0 "$(calls set-option)"
new_case p10
TMUX="$INSIDE" FAKE_SPLIT_OUT="" run_ds myrepo HUB-841
assert_eq "split-window empty pane id - exit 4" 4 "$RC"
assert_err_has "split-window empty pane id - message" "returned no pane id"
assert_eq "split-window empty pane id - no set-option" 0 "$(calls set-option)"
new_case p11
TMUX="$INSIDE" FAKE_LIST_RC=1 run_ds myrepo HUB-841
assert_eq "list-panes failure - exit 4" 4 "$RC"
assert_eq "list-panes failure - no second claude started" 0 "$(calls split-window)"

new_case p12
run_ds myrepo HUB-841 --new-session --detach
assert_eq "--new-session outside tmux - exit 0" 0 "$RC"
assert_eq "--new-session outside tmux - exact new-session argv" "$NEW_HUB" "$(line_of new-session)"
assert_eq "--new-session outside tmux - no pane lookup" 0 "$(calls list-panes)"
new_case p13
TMUX="$INSIDE" run_ds myrepo HUB-841 --new-session --detach
assert_eq "--new-session inside tmux --detach - uses new-session" "$NEW_HUB" "$(line_of new-session)"
assert_eq "--new-session inside tmux --detach - no split-window" 0 "$(calls split-window)"
new_case p14
run_ds myrepo HUB-841 --detach
assert_eq "outside tmux - no pane mode" 0 "$(calls split-window)"
assert_eq "outside tmux - no pane lookup" 0 "$(calls list-panes)"

# ---- 12. Rex mode ($REX_SESSION set, $TMUX not) ----------------------------------------------------------
RS="session:cur"; RB="block:cur"
RX_TAIL="[--][bash][-lc][$BASHC][_][claude][--model][opus][--permission-mode][plan][-n][HUB-841][/deliver $URL1]"
RX_SPLIT="[split][-s][$RS][-b][$RB][--split=right][--label][HUB-841][-c][$GIT_ROOT/myrepo][--shell=none]"
BLK_MINE='{"blocks":[{"block_id":"block:b9","label":"HUB-841","window_id":"window:w1"}]}'
BLK_OTHERS='{"blocks":[{"block_id":"block:b1","label":"HUB-8410","window_id":"window:w1"},{"block_id":"block:b2","label":"","window_id":"window:w1"}]}'
LS_TWO='{"sessions":[{"session_id":"session:other","label":"misc"},{"session_id":"session:cur","label":"main"}]}'
LS_HAS_KEY='{"sessions":[{"session_id":"session:cur","label":"main"},{"session_id":"session:k1","label":"HUB-841"}]}'

new_case x1
REX_SESSION="$RS" REX_BLOCK="$RB" run_ds myrepo HUB-841
assert_eq "rex pane - exit 0" 0 "$RC"
assert_eq "rex pane - exact split argv" "$RX_SPLIT[--json]$RX_TAIL" "$(rline_of split)"
assert_eq "rex pane - exactly one split" 1 "$(rcalls split)"
assert_eq "rex pane - lookups then split" "ls block split" "$(rorder)"
assert_eq "rex pane - block lookup is per session, json" "[block][ls][-s][$RS][--json]" "$(rline_of block)"
assert_eq "rex pane - no tmux call" 0 "$(total_calls)"
assert_eq "rex pane - no session selection" 0 "$(rcalls do)"
assert_err_has "rex pane - reports the block" "deliver-session: started HUB-841 in block block:new1"

new_case x2
REX_SESSION="$RS" REX_BLOCK="$RB" run_ds myrepo HUB-841 --detach
assert_eq "rex pane --detach - exit 0" 0 "$RC"
assert_eq "rex pane --detach - split gets --focus=false" "$RX_SPLIT[--focus=false][--json]$RX_TAIL" "$(rline_of split)"

new_case x3
REX_SESSION="$RS" run_ds myrepo HUB-841
assert_eq "rex pane without REX_BLOCK - exit 0" 0 "$RC"
assert_eq "rex pane without REX_BLOCK - no -b" \
  "[split][-s][$RS][--split=right][--label][HUB-841][-c][$GIT_ROOT/myrepo][--shell=none][--json]$RX_TAIL" "$(rline_of split)"

new_case x4
REX_SESSION="$RS" REX_BLOCK="$RB" FAKE_REX_BLOCKS="$BLK_MINE" run_ds myrepo HUB-841
assert_eq "rex existing block - exit 0" 0 "$RC"
assert_eq "rex existing block - no split" 0 "$(rcalls split)"
assert_eq "rex existing block - no new" 0 "$(rcalls new)"
assert_eq "rex existing block - focuses it" "[focus][-s][$RS][block:b9]" "$(rline_of focus)"
assert_err_has "rex existing block - message" "deliver-session: block block:b9 already running HUB-841, focusing it"

new_case x5
REX_SESSION="$RS" REX_BLOCK="$RB" FAKE_REX_LS="$LS_TWO" FAKE_REX_BLOCKS="$BLK_MINE" FAKE_REX_BLOCKS_SESSION="session:other" run_ds myrepo HUB-841
assert_eq "rex block in another session - exit 0" 0 "$RC"
assert_eq "rex block in another session - focus is scoped to that session" "[focus][-s][session:other][block:b9]" "$(rline_of focus)"
assert_eq "rex block in another session - no split" 0 "$(rcalls split)"
assert_err_has "rex block in another session - names the session" "in session session:other"

new_case x6
REX_SESSION="$RS" REX_BLOCK="$RB" FAKE_REX_BLOCKS="$BLK_MINE" run_ds myrepo HUB-841 --detach
assert_eq "rex existing block --detach - exit 0" 0 "$RC"
assert_eq "rex existing block --detach - no focus" 0 "$(rcalls focus)"
assert_eq "rex existing block --detach - no split" 0 "$(rcalls split)"
assert_err_has "rex existing block --detach - message" "not focusing (--detach)"

new_case x7
REX_SESSION="$RS" REX_BLOCK="$RB" FAKE_REX_BLOCKS="$BLK_OTHERS" run_ds myrepo HUB-841
assert_eq "rex other labels are not a match - split ran" 1 "$(rcalls split)"

new_case x8
REX_SESSION="$RS" REX_BLOCK="$RB" FAKE_REX_RC=1 FAKE_REX_FAIL_ON=block run_ds myrepo HUB-841
assert_eq "rex block listing failure - exit 4" 4 "$RC"
assert_eq "rex block listing failure - no second claude started" 0 "$(rcalls split)"
assert_eq "rex block listing failure - no tmux fallback" 0 "$(total_calls)"
assert_err_has "rex block listing failure - message" "rex block listing failed"
new_case x8b
REX_SESSION="$RS" REX_BLOCK="$RB" FAKE_REX_RC=1 FAKE_REX_FAIL_ON=ls run_ds myrepo HUB-841
assert_eq "rex ls failure - exit 4" 4 "$RC"
assert_eq "rex ls failure - nothing created" 0 "$(rcalls split)"
assert_eq "rex ls failure - no tmux fallback" 0 "$(total_calls)"
new_case x8c
REX_SESSION="$RS" REX_BLOCK="$RB" FAKE_REX_BLOCKS="not json" run_ds myrepo HUB-841
assert_eq "rex unreadable block listing - exit 4" 4 "$RC"
assert_eq "rex unreadable block listing - no split" 0 "$(rcalls split)"

new_case x9
REX_SESSION="$RS" REX_BLOCK="$RB" FAKE_REX_RC=1 FAKE_REX_FAIL_ON=split run_ds myrepo HUB-841
assert_eq "rex split failure - exit 4" 4 "$RC"
assert_err_has "rex split failure - message" "rex split for HUB-841 failed"
assert_eq "rex split failure - no tmux fallback" 0 "$(total_calls)"
new_case x9b
REX_SESSION="$RS" REX_BLOCK="$RB" FAKE_REX_SPLIT_OUT="" run_ds myrepo HUB-841
assert_eq "rex split without output - exit 4" 4 "$RC"
assert_err_has "rex split without output - message" "returned no block id"
new_case x9c
REX_SESSION="$RS" REX_BLOCK="$RB" FAKE_REX_SPLIT_OUT='{"block_ids":[]}' run_ds myrepo HUB-841
assert_eq "rex split with no block ids - exit 4" 4 "$RC"

new_case x10
REX_SESSION="$RS" REX_BLOCK="$RB" run_ds myrepo HUB-841 --new-session --detach
assert_eq "rex --new-session - exit 0" 0 "$RC"
assert_eq "rex --new-session - exact new argv" "[new][HUB-841][-c][$GIT_ROOT/myrepo][--shell=none][--json]$RX_TAIL" "$(rline_of new)"
assert_eq "rex --new-session - no split" 0 "$(rcalls split)"
assert_eq "rex --new-session - no block lookup" 0 "$(rcalls block)"
assert_eq "rex --new-session --detach - session is not selected" 0 "$(rcalls do)"
assert_eq "rex --new-session - no tmux call" 0 "$(total_calls)"
new_case x10b
REX_SESSION="$RS" REX_BLOCK="$RB" run_ds myrepo HUB-841 --new-session
assert_eq "rex --new-session attach - exit 0" 0 "$RC"
assert_eq "rex --new-session attach - selects the new session" "[do][session.select][session_id=session:new1]" "$(rline_of do)"
new_case x10c
REX_SESSION="$RS" REX_BLOCK="$RB" REX_CLIENT="mac mini" run_ds myrepo HUB-841 --new-session
assert_eq "rex REX_CLIENT - passed as -C before the subcommand" "[-C][mac mini][do][session.select][session_id=session:new1]" "$(rline_of do)"
new_case x10d
REX_SESSION="$RS" REX_BLOCK="$RB" FAKE_REX_RC=1 FAKE_REX_FAIL_ON=new run_ds myrepo HUB-841 --new-session
assert_eq "rex new failure - exit 4" 4 "$RC"
assert_err_has "rex new failure - message" "rex new for HUB-841 failed"
assert_eq "rex new failure - nothing selected" 0 "$(rcalls do)"
new_case x10e
REX_SESSION="$RS" REX_BLOCK="$RB" FAKE_REX_NEW_OUT="" run_ds myrepo HUB-841 --new-session
assert_eq "rex new without output - exit 4" 4 "$RC"
assert_err_has "rex new without output - message" "returned no session id"

new_case x11
REX_SESSION="$RS" REX_BLOCK="$RB" FAKE_REX_RC=1 FAKE_REX_FAIL_ON=do run_ds myrepo HUB-841 --new-session
assert_eq "rex failed session.select - exit 0 (non-fatal)" 0 "$RC"
assert_eq "rex failed session.select - the session was created" 1 "$(rcalls new)"
assert_err_has "rex failed session.select - points at the sidebar" "open session HUB-841 in the Rex sidebar"

new_case x12
REX_SESSION="$RS" REX_BLOCK="$RB" FAKE_REX_LS="$LS_HAS_KEY" run_ds myrepo HUB-841
assert_eq "rex existing session - exit 0" 0 "$RC"
assert_eq "rex existing session - no split" 0 "$(rcalls split)"
assert_eq "rex existing session - no new" 0 "$(rcalls new)"
assert_eq "rex existing session - selects it" "[do][session.select][session_id=session:k1]" "$(rline_of do)"
assert_err_has "rex existing session - message" "session HUB-841 already exists, selecting it"
new_case x12b
REX_SESSION="$RS" REX_BLOCK="$RB" FAKE_REX_LS="$LS_HAS_KEY" run_ds myrepo HUB-841 --detach
assert_eq "rex existing session --detach - exit 0" 0 "$RC"
assert_eq "rex existing session --detach - no select" 0 "$(rcalls do)"
assert_eq "rex existing session --detach - no split" 0 "$(rcalls split)"
new_case x12c
REX_SESSION="$RS" REX_BLOCK="$RB" FAKE_REX_LS="$LS_HAS_KEY" FAKE_REX_BLOCKS="$BLK_MINE" run_ds myrepo HUB-841
assert_eq "rex block and session both exist - the block wins" "[focus][-s][$RS][block:b9]" "$(rline_of focus)"
assert_eq "rex block and session both exist - session not selected" 0 "$(rcalls do)"

new_case x13
REX_SESSION="$RS" REX_BLOCK="$RB" run_ds myrepo HUB-841 --dry-run
assert_eq "rex --dry-run - exit 0" 0 "$RC"
assert_eq "rex --dry-run - only the read-only lookups ran" "ls block" "$(rorder)"
assert_out_has "rex --dry-run - prints split" "split -s session:cur -b block:cur --split=right --label HUB-841"
eval "DRY_ARGV=($OUT)"
assert_eq "rex --dry-run - round-trips: rex binary" "$FAKE_REX" "${DRY_ARGV[0]}"
assert_eq "rex --dry-run - round-trips: pane script is one argument" "$BASHC" "${DRY_ARGV[16]}"
assert_eq "rex --dry-run - round-trips: last argument" "/deliver $URL1" "${DRY_ARGV[${#DRY_ARGV[@]}-1]}"
assert_eq "rex --dry-run - round-trips: argument count" 26 "${#DRY_ARGV[@]}"
new_case x13b
CLAUDE_BIN="/opt/my claude/bin/cl'aude" REX_SESSION="$RS" REX_BLOCK="$RB" run_ds myrepo HUB-841 --dry-run -d
eval "DRY_ARGV=($OUT)"
assert_eq "rex --dry-run --detach - prints --focus=false" "--focus=false" "${DRY_ARGV[12]}"
assert_eq "rex --dry-run - CLAUDE_BIN arrives as one argument" "/opt/my claude/bin/cl'aude" "${DRY_ARGV[19]}"
new_case x13c
REX_SESSION="$RS" REX_BLOCK="$RB" run_ds myrepo HUB-841 --dry-run --new-session
eval "DRY_ARGV=($OUT)"
assert_eq "rex --dry-run --new-session - prints new" "new" "${DRY_ARGV[1]}"
assert_eq "rex --dry-run --new-session - session label" "HUB-841" "${DRY_ARGV[2]}"
assert_eq "rex --dry-run --new-session - nothing created" "ls" "$(rorder)"
new_case x13d
REX_SESSION="$RS" REX_BLOCK="$RB" FAKE_REX_BLOCKS="$BLK_MINE" run_ds myrepo HUB-841 --dry-run
assert_eq "rex --dry-run with existing block - exit 0" 0 "$RC"
assert_eq "rex --dry-run with existing block - nothing focused" 0 "$(rcalls focus)"

new_case x14
DS_REX="$WORK/no-such-rex" REX_SESSION="$RS" REX_BLOCK="$RB" run_ds myrepo HUB-841
assert_eq "rex missing - exit 3" 3 "$RC"
assert_err_has "rex missing - message" "rex not found"
assert_eq "rex missing - no tmux fallback" 0 "$(total_calls)"

new_case x15
TMUX="$INSIDE" REX_SESSION="$RS" REX_BLOCK="$RB" run_ds myrepo HUB-841
assert_eq "TMUX and REX_SESSION both set - exit 0" 0 "$RC"
assert_eq "TMUX and REX_SESSION both set - tmux splits" 1 "$(calls split-window)"
assert_eq "TMUX and REX_SESSION both set - zero rex calls" 0 "$(rtotal)"
new_case x15b
TMUX="$INSIDE" REX_SESSION="$RS" REX_BLOCK="$RB" run_ds myrepo HUB-841 --new-session --detach
assert_eq "TMUX and REX_SESSION, --new-session - tmux new-session" "$NEW_HUB" "$(line_of new-session)"
assert_eq "TMUX and REX_SESSION, --new-session - zero rex calls" 0 "$(rtotal)"

new_case x16
DS_TMUX="$WORK/no-such-tmux" REX_SESSION="$RS" REX_BLOCK="$RB" run_ds myrepo HUB-841
assert_eq "rex mode needs no tmux - exit 0" 0 "$RC"
assert_eq "rex mode needs no tmux - split ran" 1 "$(rcalls split)"
new_case x16b
REX_BLOCK="$RB" run_ds myrepo HUB-841 --detach
assert_eq "REX_BLOCK alone does not select rex - tmux session created" 1 "$(calls new-session)"
assert_eq "REX_BLOCK alone does not select rex - zero rex calls" 0 "$(rtotal)"

# ---- 13. usage ---------------------------------------------------------------------------------------
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
