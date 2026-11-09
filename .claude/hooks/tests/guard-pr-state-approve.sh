#!/bin/bash
#
# Tests for the raw-approval block and the push-to-approved-PR warning in
# hooks/guard-pr-state.sh. Synthetic inputs only. A stub `gh` is placed first on
# PATH so no test can reach the network; it answers `gh pr view --json ...` from
# the STUB_* environment variables and records every call.
# Usage: bash hooks/tests/guard-pr-state-approve.sh
# Override the hook under test with HOOK=/path/to/copy.sh (used for mutation checks).

HOOK="${HOOK:-$(cd "$(dirname "$0")/.." && pwd)/guard-pr-state.sh}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/nongit" "$WORK/repo"
GH_LOG="$WORK/gh-calls.log"

# Stub gh: `pr view <branch> --json state` prints $STUB_STATE; `--json number,latestReviews`
# prints $STUB_REVIEWS. STUB_GH_FAIL=1 makes every call exit 1 with no output.
cat >"$WORK/bin/gh" <<EOF
#!/bin/bash
echo "\$@" >>"$GH_LOG"
[ "\${STUB_GH_FAIL:-}" = 1 ] && exit 1
case "\$*" in
  *"--json state"*) printf '%s\n' "\${STUB_STATE-OPEN}" ;;
  *"--json number,latestReviews"*) printf '%s\n' "\${STUB_REVIEWS:-}" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$WORK/bin/gh"

git -C "$WORK/repo" init -q -b feature 2>/dev/null || {
  git -C "$WORK/repo" init -q && git -C "$WORK/repo" checkout -q -b feature
}
# `rev-parse --abbrev-ref HEAD` needs a commit to report the branch name.
git -C "$WORK/repo" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false \
  commit -q --allow-empty -m init

# Payload files for `gh api --input`.
printf '{"event":"APPROVE","body":"ok","commit_id":"abc"}' >"$WORK/approve.json"
printf '{"event":"COMMENT","body":"ok"}' >"$WORK/comment.json"

PASS=0
FAIL=0

json_bash() {
  CMD="$1" python3 -c 'import json,os;print(json.dumps({"tool_name":"Bash","tool_input":{"command":os.environ["CMD"]}}))'
}

# run_hook CWD COMMAND -> sets RC, OUT (stdout), ERR (stderr)
run_hook() {
  local cwd="$1" cmd="$2" errf="$WORK/err.txt"
  OUT=$(cd "$cwd" && json_bash "$cmd" | PATH="$WORK/bin:$PATH" bash "$HOOK" 2>"$errf")
  RC=$?
  ERR=$(cat "$errf")
}

ok() {
  PASS=$((PASS + 1))
  echo "PASS: $1"
}
bad() {
  FAIL=$((FAIL + 1))
  echo "FAIL: $1 $2"
}

# blocked NAME COMMAND : exit 2, message names pr-approve, nothing on stdout
blocked() {
  run_hook "$WORK/nongit" "$2"
  if [ "$RC" -eq 2 ] && [[ "$ERR" == *"pr-approve"* ]] && [ -z "$OUT" ]; then ok "$1"; else bad "$1" "(want exit 2 naming pr-approve, got $RC) $ERR"; fi
}

# passes NAME COMMAND : exit 0, no stdout (outside a git repo)
passes() {
  run_hook "$WORK/nongit" "$2"
  if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then ok "$1"; else bad "$1" "(want exit 0, got $RC) $ERR"; fi
}

# --- Blocked: raw approvals ---
blocked 'gh pr review --approve blocked' 'gh pr review 12 --approve'
blocked 'gh pr review -a blocked' 'gh pr review 12 -a'
blocked 'gh pr review --approve with body blocked' 'gh pr review 12 --approve --body "lgtm"'
blocked 'gh pr review -a -b body blocked' 'gh pr review 12 -a -b "lgtm"'
blocked 'gh pr review --approve=true blocked' 'gh pr review 12 --approve=true'
blocked 'gh pr review --approve with -R before PR blocked' 'gh pr review --approve -R o/r 12'
blocked 'gh pr review --approve chained blocked' 'git status && gh pr review 12 --approve'
blocked 'path-qualified gh pr review --approve blocked' '/opt/homebrew/bin/gh pr review 12 --approve'
blocked 'env-prefixed gh pr review --approve blocked' 'GH_TOKEN=x gh pr review 12 --approve'
blocked 'gh api reviews -f event=APPROVE blocked' 'gh api repos/o/r/pulls/12/reviews -f event=APPROVE'
blocked 'gh api reviews -F event=APPROVE blocked' 'gh api repos/o/r/pulls/12/reviews -F event=APPROVE'
blocked 'gh api reviews -f "event=APPROVE" (quoted) blocked' 'gh api repos/o/r/pulls/12/reviews -f "event=APPROVE" -f body=x'
blocked 'gh api reviews --raw-field event=APPROVE blocked' 'gh api repos/o/r/pulls/12/reviews --raw-field event=APPROVE'
blocked 'gh api reviews --field=event=APPROVE blocked' 'gh api repos/o/r/pulls/12/reviews --field=event=APPROVE'
blocked 'gh api reviews -fevent=APPROVE blocked' 'gh api repos/o/r/pulls/12/reviews -fevent=APPROVE'
blocked 'gh api reviews event=approve (lowercase) blocked' 'gh api repos/o/r/pulls/12/reviews -f event=approve'
blocked 'gh api -X POST reviews event=APPROVE blocked' 'gh api -X POST repos/o/r/pulls/12/reviews -f event=APPROVE -f commit_id=abc'
blocked 'gh api submit pending review event=APPROVE blocked' 'gh api repos/o/r/pulls/12/reviews/99/events -f event=APPROVE'
blocked 'gh api --input file with event APPROVE blocked' "gh api repos/o/r/pulls/12/reviews --input $WORK/approve.json"
blocked 'gh api --input - heredoc with event APPROVE blocked' 'gh api repos/o/r/pulls/12/reviews --input - <<EOF
{"event": "APPROVE", "body": "x"}
EOF'
blocked 'gh api graphql addPullRequestReview APPROVE blocked' 'gh api graphql -f query='"'"'mutation { addPullRequestReview(input:{pullRequestId:"X", event: APPROVE}) { clientMutationId } }'"'"''

# --- Pass-throughs ---
passes 'gh pr review --comment passes' 'gh pr review 12 --comment --body "looks fine"'
passes 'gh pr review --request-changes passes' 'gh pr review 12 --request-changes --body "fix it"'
passes 'gh pr review -r passes' 'gh pr review 12 -r -b "fix it"'
passes 'gh pr review body text "-a" passes' 'gh pr review 12 --comment --body "-a"'
passes 'gh pr review body text --approve passes' 'gh pr review 12 --comment --body "please --approve later"'
passes 'gh pr view passes' 'gh pr view 12'
passes 'gh pr view --json passes' 'gh pr view 12 --json latestReviews'
# shellcheck disable=SC2088  # the tilde is literal command text for the hook, not meant to expand
passes 'pr-approve passes' '~/.claude/bin/pr-approve 12 --sha abc1234 -R o/r --body-file /tmp/b.md'
passes 'pr-approve dry run passes' 'pr-approve 1 --sha abc -n'
passes 'echo mentioning gh pr review --approve passes' 'echo gh pr review 12 --approve'
passes 'gh api reviews event=COMMENT passes' 'gh api repos/o/r/pulls/12/reviews -f event=COMMENT -f body=x'
passes 'gh api reviews event=REQUEST_CHANGES passes' 'gh api repos/o/r/pulls/12/reviews -f event=REQUEST_CHANGES'
passes 'gh api reviews --input file with event COMMENT passes' "gh api repos/o/r/pulls/12/reviews --input $WORK/comment.json"
passes 'gh api reviews --input unreadable file passes (ambiguous)' 'gh api repos/o/r/pulls/12/reviews --input /nonexistent/payload.json'
passes 'gh api GET reviews passes' 'gh api repos/o/r/pulls/12/reviews'
passes 'gh api event=APPROVE on a non-review path passes' 'gh api repos/o/r/issues/12/comments -f event=APPROVE'
passes 'gh api graphql read-only passes' 'gh api graphql -f query='"'"'{ viewer { login } }'"'"''

# --- Push: approvals warning (needs a real git work tree on a branch; gh is the stub) ---
# push_case NAME EXPECTED_RC EXPECT(warn|silent|block) STATE REVIEWS [GH_FAIL]
push_case() {
  local name="$1" want_rc="$2" expect="$3"
  : >"$GH_LOG"
  STUB_STATE="$4" STUB_REVIEWS="$5" STUB_GH_FAIL="${6:-}" run_hook_env "$WORK/repo" 'git push origin feature'
  local ctx=""
  if [ -n "$OUT" ]; then
    ctx=$(printf '%s' "$OUT" | python3 -c '
import json, sys
d = json.load(sys.stdin)
h = d["hookSpecificOutput"]
assert h["hookEventName"] == "PreToolUse", h
print(h["additionalContext"])' 2>&1)
  fi
  case "$expect" in
    warn)
      if [ "$RC" -eq "$want_rc" ] && [[ "$ctx" == *"has $7 approval(s)"* ]] && [[ "$ctx" == *"PR #$8 "* ]]; then ok "$name"; else bad "$name" "(rc=$RC ctx=[$ctx] err=[$ERR])"; fi
      ;;
    silent)
      if [ "$RC" -eq "$want_rc" ] && [ -z "$OUT" ]; then ok "$name"; else bad "$name" "(rc=$RC out=[$OUT] err=[$ERR])"; fi
      ;;
    block)
      if [ "$RC" -eq "$want_rc" ] && [ -z "$OUT" ] && [[ "$ERR" == *"already"* ]]; then ok "$name"; else bad "$name" "(rc=$RC out=[$OUT] err=[$ERR])"; fi
      ;;
  esac
}

# Same as run_hook but passes the STUB_* variables through to the hook's gh stub.
run_hook_env() {
  local cwd="$1" cmd="$2" errf="$WORK/err.txt"
  OUT=$(cd "$cwd" && json_bash "$cmd" | STUB_STATE="$STUB_STATE" STUB_REVIEWS="$STUB_REVIEWS" STUB_GH_FAIL="$STUB_GH_FAIL" PATH="$WORK/bin:$PATH" bash "$HOOK" 2>"$errf")
  RC=$?
  ERR=$(cat "$errf")
}

push_case 'push to open PR with 2 approvals warns (allowed)' 0 warn OPEN '42 2' "" 2 42
push_case 'push to open PR with 1 approval warns (allowed)' 0 warn OPEN '7 1' "" 1 7
push_case 'push to open PR with 0 approvals is silent' 0 silent OPEN '42 0'
push_case 'push with unparseable review output is silent' 0 silent OPEN 'garbage'
push_case 'push with empty review output is silent' 0 silent OPEN ''
push_case 'push when gh fails is silent' 0 silent OPEN '42 2' 1
push_case 'push to merged PR still blocked' 2 block MERGED '42 2'
push_case 'push to closed PR still blocked' 2 block CLOSED '42 2'
push_case 'push with no PR (empty state) is silent' 0 silent "" '42 2'

# The warning's jq filter counts only APPROVED among latestReviews. Run the same
# filter the hook uses against fixtures, with real jq semantics via `gh`'s -q being
# jq: here jq itself, if present.
if command -v jq >/dev/null 2>&1; then
  FILTER='"\(.number) \([.latestReviews[]? | select(.state == "APPROVED")] | length)"'
  got=$(printf '%s' '{"number":9,"latestReviews":[{"state":"APPROVED"},{"state":"CHANGES_REQUESTED"},{"state":"COMMENTED"},{"state":"APPROVED"}]}' | jq -r "$FILTER")
  if [ "$got" = "9 2" ]; then ok 'latestReviews filter counts only APPROVED'; else bad 'latestReviews filter counts only APPROVED' "(got [$got])"; fi
  got=$(printf '%s' '{"number":9,"latestReviews":[]}' | jq -r "$FILTER")
  if [ "$got" = "9 0" ]; then ok 'latestReviews filter: none -> 0'; else bad 'latestReviews filter: none -> 0' "(got [$got])"; fi
fi

# The blocking path must be purely local: the raw-approval cases ran outside a git
# repo, so the stub gh must not have been called for them. (GH_LOG was reset by the
# push cases, so check it with a fresh blocked run.)
: >"$GH_LOG"
run_hook "$WORK/nongit" 'gh pr review 12 --approve'
if [ "$RC" -eq 2 ] && [ ! -s "$GH_LOG" ]; then ok 'approval block never calls gh'; else bad 'approval block never calls gh' "(rc=$RC log=$(cat "$GH_LOG"))"; fi

echo
echo "guard-pr-state-approve: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
