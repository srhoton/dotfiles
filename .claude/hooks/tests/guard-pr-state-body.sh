#!/bin/bash
#
# Tests for the gh "@path" body check in hooks/guard-pr-state.sh, plus a
# regression check that unrelated commands still pass. Synthetic inputs only.
# A stub `gh` is placed first on PATH so no test can reach the network; the stub
# records any call, and the suite fails if the blocking path ever invoked it.
# Usage: bash hooks/tests/guard-pr-state-body.sh
# Override the hook under test with HOOK=/path/to/copy.sh (used for mutation checks).

HOOK="${HOOK:-$(cd "$(dirname "$0")/.." && pwd)/guard-pr-state.sh}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/nongit"
GH_LOG="$WORK/gh-calls.log"
cat >"$WORK/bin/gh" <<EOF
#!/bin/bash
echo "\$@" >>"$GH_LOG"
exit 1
EOF
chmod +x "$WORK/bin/gh"
PASS=0
FAIL=0

json_bash() {
  CMD="$1" python3 -c 'import json,os;print(json.dumps({"tool_name":"Bash","tool_input":{"command":os.environ["CMD"]}}))'
}

# case NAME EXPECTED_RC COMMAND
case_() {
  local name="$1" want="$2" cmd="$3" got err
  err=$(cd "$WORK/nongit" && json_bash "$cmd" | PATH="$WORK/bin:$PATH" bash "$HOOK" 2>&1 >/dev/null)
  got=$?
  if [ "$got" -eq "$want" ]; then
    PASS=$((PASS + 1))
    echo "PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $name (want exit $want, got $got) $err"
  fi
}

# Blocked: @path in a body/message argument
case_ 'gh pr create --body "@x.md" blocked' 2 'gh pr create --title t --body "@x.md"'
case_ "gh pr create --body '@x.md' blocked" 2 "gh pr create --title t --body '@x.md'"
case_ 'gh pr create --body @x.md (unquoted) blocked' 2 'gh pr create --title t --body @x.md'
case_ 'gh pr create --body=@x.md blocked' 2 'gh pr create --body=@x.md'
case_ 'gh pr create -b "@x.md" blocked' 2 'gh pr create -b "@x.md"'
case_ 'gh pr create -b@x.md blocked' 2 'gh pr create -b@x.md'
case_ 'gh pr comment --body "@x.md" blocked' 2 'gh pr comment 12 --body "@x.md"'
case_ 'gh pr review --comment "@x" blocked' 2 'gh pr review 12 --comment "@x.md"'
case_ 'gh issue create --message @x blocked' 2 'gh issue create --message "@x.md"'
case_ 'gh pr merge --body "@x.md" blocked' 2 'gh pr merge 5 --body "@x.md"'
case_ 'gh pr merge -b "@x.md" blocked' 2 'gh pr merge 5 -b "@x.md"'
case_ 'gh pr merge --body=@x.md blocked' 2 'gh pr merge 5 --body=@x.md'
case_ 'gh pr merge -m -b "@x.md" blocked' 2 'gh pr merge 5 -m -b "@x.md"'
case_ 'gh release create --notes "@x.md" blocked' 2 'gh release create v1 --notes "@x.md"'
case_ 'gh release create --notes=@x.md blocked' 2 'gh release create v1 --notes=@x.md'
case_ 'gh release create -n "@x.md" blocked' 2 'gh release create v1 -n "@x.md"'
case_ 'gh release edit --notes "@x.md" blocked' 2 'gh release edit v1 --notes "@x.md"'
case_ 'gh release edit --notes=@x.md blocked' 2 'gh release edit v1 --notes=@x.md'
case_ 'path-qualified gh blocked' 2 '/usr/bin/gh pr create --body "@x.md"'
case_ 'subshell gh blocked' 2 'echo $(gh pr create --body "@x.md")'
case_ 'quoted gh word blocked' 2 '"gh" pr create --body "@x.md"'
case_ 'gh api -f body=@x blocked' 2 'gh api repos/o/r/issues/1/comments -f body=@x.md'
case_ 'gh api -f "body=@x" (quoted) blocked' 2 'gh api repos/o/r/issues/1/comments -f "body=@x.md"'
case_ 'gh api --raw-field body=@x blocked' 2 'gh api repos/o/r/issues/1/comments --raw-field body=@x.md'
case_ 'gh api --raw-field=body=@x blocked' 2 'gh api repos/o/r/issues/1/comments --raw-field=body=@x.md'
case_ 'chained: git status && gh pr create --body @x blocked' 2 'git status && gh pr create --body "@x.md"'
case_ 'env-prefixed gh blocked' 2 'GH_TOKEN=x gh pr create --body "@x.md"'

# Allowed: correct usages and non-matches
case_ 'gh pr create --body-file allowed' 0 'gh pr create --title t --body-file /tmp/body.md'
case_ 'gh pr create --body-file - allowed' 0 'gh pr create --body-file -'
case_ 'gh pr create --body plain text allowed' 0 'gh pr create --title t --body "hello world"'
case_ 'gh pr create body mentioning @user mid-text allowed' 0 'gh pr create --body "cc @someone for review"'
case_ 'gh api --input allowed' 0 'gh api repos/o/r/issues/1/comments --input /tmp/payload.json'
case_ 'gh api -f body=text allowed' 0 'gh api repos/o/r/issues/1/comments -f body="hi there"'
case_ 'gh api -F body=@file allowed (gh expands -F)' 0 'gh api repos/o/r/issues/1/comments -F body=@x.md'
case_ 'gh api -f other=@x allowed (not body)' 0 'gh api repos/o/r/x -f note=@x.md'
case_ 'gh pr merge -m (flag, no value) allowed' 0 'gh pr merge 5 -m --delete-branch'
case_ 'gh pr merge -m "@x.md" allowed (-m is --merge, not a message)' 0 'gh pr merge 5 -m "@x.md"'
case_ 'gh pr merge --body plain allowed' 0 'gh pr merge 5 --body "done"'
case_ 'gh pr create -m "@x" still blocked (-m is a message flag outside pr merge)' 2 'gh pr create -m "@x.md"'
case_ 'gh release create --notes plain allowed' 0 'gh release create v1 --notes "hello"'
case_ 'gh release create --notes-file allowed' 0 'gh release create v1 --notes-file /tmp/n.md'
case_ 'gh pr create --notes "@x" allowed (--notes only for release)' 0 'gh pr create --notes "@x.md"'
case_ 'text containing "gh" in a word is ignored' 0 'echo "ahigh pr create --body @x.md"; ls highlight.txt'
case_ 'echo mentioning gh --body @ allowed' 0 'echo gh pr create --body @x.md'
case_ 'body heredoc via command substitution allowed' 0 'gh pr create --body "$(cat <<'"'"'EOF'"'"'
text with @mention
EOF
)"'

# Regression: existing behavior intact
case_ 'git status allowed' 0 'git status'
case_ 'ls allowed' 0 'ls -la'
case_ 'git push outside a git repo allowed' 0 'git push origin main'
case_ 'gh pr view allowed' 0 'gh pr view 12'

# The blocking path must be purely local: the only gh calls permitted are none
# (the non-git cwd means even `git push` exits before calling gh).
if [ -s "$GH_LOG" ]; then
  FAIL=$((FAIL + 1))
  echo "FAIL: stub gh was invoked: $(cat "$GH_LOG")"
else
  PASS=$((PASS + 1))
  echo "PASS: gh was never invoked (no network path reached)"
fi

echo
echo "guard-pr-state-body: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
