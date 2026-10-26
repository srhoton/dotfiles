#!/bin/bash
#
# Tests for commit-notes. Every case builds a throwaway repo in a temp dir with
# a bare "origin" next to it; no real remote, no GitHub call. `gh` is replaced
# through the GH env var by a stub that prints a scripted PR line. Claude Code
# hooks are redirected to stub directories through COMMIT_NOTES_HOOKS_DIR
# (except one case that runs the real pre-commit-checks.sh in a plain repo).
# All fixture names and contents are invented.
#
# Usage: bin/tests/commit-notes.sh      (exit 1 if any case fails)
#        COMMIT_NOTES=<path> bin/tests/commit-notes.sh   (test another copy)

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
CN=${COMMIT_NOTES:-$HERE/../commit-notes}
REAL_HOOKS=$(cd "$HERE/../../hooks" 2>/dev/null && pwd)
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

# Isolate from the caller's git config; commits and pushes never prompt.
printf '[user]\n\tname = Test User\n\temail = test@example.test\n[init]\n\tdefaultBranch = main\n[commit]\n\tgpgsign = false\n' > "$WORK/gitconfig"
export GIT_CONFIG_GLOBAL="$WORK/gitconfig" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
unset GIT_INDEX_FILE GIT_DIR GIT_WORK_TREE

mkdir -p "$WORK/nohooks"
export COMMIT_NOTES_HOOKS_DIR="$WORK/nohooks"

# gh stub: `pr view` prints $FAKE_PR (number<TAB>state<TAB>base) or fails when
# FAKE_PR is "none"; every call is logged.
cat > "$WORK/gh" <<'EOS'
#!/bin/bash
echo "$*" >> "$WORK_LOG"
case "$1 $2" in
  "pr view") [ "${FAKE_PR:-none}" = none ] && exit 1; printf '%b\n' "$FAKE_PR" ;;
  *) echo "stub gh: unexpected call: $*" >&2; exit 99 ;;
esac
EOS
chmod +x "$WORK/gh"
export GH="$WORK/gh" WORK_LOG="$WORK/gh.log"

ok()  { PASS=$((PASS + 1)); echo "ok    $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL  $1"; echo "      got: $2"; }
expect() {  # CASE OUTPUT PATTERN  (extended regex that must match)
  if printf '%s\n' "$2" | grep -Eq -- "$3"; then ok "$1"; else bad "$1 (wanted /$3/)" "$2"; fi
}
reject() {  # CASE OUTPUT PATTERN  (extended regex that must NOT match)
  if printf '%s\n' "$2" | grep -Eq -- "$3"; then bad "$1 (did not want /$3/)" "$2"; else ok "$1"; fi
}
eq() {  # CASE ACTUAL EXPECTED
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "'$2' (wanted '$3')"; fi
}

NEXT=0
# mkrepo -> sets R (work tree) and O (bare origin). main is pushed, origin/HEAD
# is set, and a feature branch is checked out. SETHEAD=0 leaves origin/HEAD unset.
mkrepo() {
  NEXT=$((NEXT + 1))
  O="$WORK/r$NEXT/origin.git"; R="$WORK/r$NEXT/work"
  mkdir -p "$WORK/r$NEXT"
  git init -q --bare "$O"
  git init -q -b "${BASEBR:-main}" "$R"
  git -C "$R" remote add origin "$O"
  echo base > "$R/base.txt"
  git -C "$R" add base.txt
  git -C "$R" commit -q -m "base"
  git -C "$R" push -q -u origin "${BASEBR:-main}"
  [ "${SETHEAD:-1}" = 1 ] && git -C "$R" remote set-head origin "${BASEBR:-main}"
  git -C "$R" switch -q -c feature/synthetic
  printf '%s\n' "msg$NEXT" > "$WORK/msg$NEXT.txt"
  MSGF="$WORK/msg$NEXT.txt"
  printf '%s\n' "prompt: synthetic note $NEXT" > "$WORK/notes$NEXT.txt"
  NOTEF="$WORK/notes$NEXT.txt"
}

cn() {  # runs commit-notes inside $R; sets OUT (stdout+stderr) and RC
  OUT=$(cd "$R" && "$CN" "$@" 2>&1); RC=$?
}

# ---- structure ------------------------------------------------------------------
bash -n "$CN" && ok "bash -n passes" || bad "bash -n" "syntax error"
[ -x "$CN" ] && ok "script is executable" || bad "script is executable" "$CN"
if grep -nE -e '--no-verify|core\.hooksPath|HUSKY=0' "$CN" >/dev/null; then
  bad "script never skips hooks" "$(grep -nE -e '--no-verify|core\.hooksPath|HUSKY=0' "$CN")"
else ok "script never skips hooks (no --no-verify, hooksPath override, HUSKY=0)"; fi
if grep -nE '(git[[:space:]]+(commit|push)|step[[:space:]]+git[[:space:]]+(commit|push))[^|#]*[[:space:]]-[A-Za-z]*n([[:space:]]|$)' "$CN" >/dev/null; then
  bad "no -n flag on git commit or git push" "$(grep -nE '(git[[:space:]]+(commit|push)|step[[:space:]]+git[[:space:]]+(commit|push))[^|#]*[[:space:]]-[A-Za-z]*n([[:space:]]|$)' "$CN")"
else ok "no -n flag on git commit or git push"; fi
if grep -nE 'git[[:space:]]+(add[[:space:]]+(-A|\.|--all)|commit[^#]*[[:space:]]-m[[:space:]])' "$CN" >/dev/null; then
  bad "never git add -A / . and never inline commit -m" "$(grep -nE 'git[[:space:]]+(add[[:space:]]+(-A|\.|--all)|commit[^#]*[[:space:]]-m[[:space:]])' "$CN")"
else ok "never git add -A / . and never inline commit -m"; fi

# ---- happy path: --add, notes, push with -u then plain --------------------------
mkrepo
echo one > "$R/a.txt"; echo two > "$R/b.txt"
cn -m "$MSGF" -n "$NOTEF" --add a.txt --push
eq "happy path exits 0" "$RC" 0
expect "  prints the staged stat" "$OUT" "a\.txt \| 1 \+"
expect "  first push sets the upstream with -u origin HEAD" "$OUT" "\+ git push -u origin HEAD"
expect "  prints pushed <sha7> to <branch>" "$OUT" "commit-notes: pushed $(git -C "$R" rev-parse --short=7 HEAD) to feature/synthetic"
eq "  commit subject is the message file" "$(git -C "$R" log -1 --format=%s)" "msg$NEXT"
eq "  only the --add path was committed" "$(git -C "$R" show --name-only --format= HEAD)" "a.txt"
eq "  b.txt stayed out of the commit" "$(git -C "$R" status --porcelain)" "?? b.txt"
eq "  note text is attached to HEAD" "$(git -C "$R" notes show HEAD)" "prompt: synthetic note $NEXT"
eq "  upstream is set" "$(git -C "$R" rev-parse --abbrev-ref '@{u}')" "origin/feature/synthetic"
eq "  origin has the pushed commit" "$(git --git-dir="$O" rev-parse feature/synthetic)" "$(git -C "$R" rev-parse HEAD)"
expect "  warns about the untracked file left behind" "$OUT" "WARNING: untracked files are NOT part of this commit"
expect "  and names it" "$OUT" "^  b\.txt$"
expect "  says there is no PR yet" "$OUT" "no PR found for feature/synthetic"

echo three >> "$R/a.txt"
cn -m "$MSGF" --add a.txt --push
eq "second push exits 0" "$RC" 0
expect "  uses plain git push" "$OUT" "^\+ git push$"
reject "  without -u" "$OUT" "git push -u"
eq "  origin has the second commit" "$(git --git-dir="$O" rev-parse feature/synthetic)" "$(git -C "$R" rev-parse HEAD)"
reject "  no notes push when the remote has no notes ref" "$OUT" "refs/notes/commits"

# ---- nothing staged -------------------------------------------------------------
mkrepo
before=$(git -C "$R" rev-parse HEAD)
cn -m "$MSGF"
eq "nothing staged and no --add exits 3" "$RC" 3
expect "  says nothing is staged" "$OUT" "nothing is staged"
eq "  no commit was made" "$(git -C "$R" rev-parse HEAD)" "$before"
echo x > "$R/clean.txt"; git -C "$R" add clean.txt; git -C "$R" commit -q -m seed
cn -m "$MSGF" --add clean.txt
eq "--add of an unchanged tracked file exits 3" "$RC" 3
expect "  says there is no change to stage" "$OUT" "no change to stage"

# ---- staged-only (no --add) -----------------------------------------------------
mkrepo
echo s > "$R/pre.txt"; git -C "$R" add pre.txt
cn -m "$MSGF"
eq "no --add commits what is already staged" "$RC" 0
eq "  and it is the staged file" "$(git -C "$R" show --name-only --format= HEAD)" "pre.txt"
expect "  and reports it was not pushed" "$OUT" "committed [0-9a-f]{7} on feature/synthetic \(not pushed\)"

# ---- --add path matching nothing ------------------------------------------------
mkrepo
echo r > "$R/real.txt"
before=$(git -C "$R" rev-parse HEAD)
cn -m "$MSGF" --add real.txt nope.txt
eq "--add with a path matching nothing exits 3" "$RC" 3
expect "  names the path" "$OUT" "'nope\.txt' matches nothing"
eq "  nothing was staged (real.txt still untracked)" "$(git -C "$R" status --porcelain)" "?? real.txt"
eq "  no commit was made" "$(git -C "$R" rev-parse HEAD)" "$before"
cn -m "$MSGF" --add 'no-such-*.txt'
eq "an unmatched glob exits 3" "$RC" 3

# ---- tracked deletion -----------------------------------------------------------
mkrepo
rm "$R/base.txt"
cn -m "$MSGF" --add base.txt
eq "a tracked deletion can be --add'ed" "$RC" 0
eq "  and the commit deletes it" "$(git -C "$R" show --name-status --format= HEAD)" "$(printf 'D\tbase.txt')"

# ---- default-branch refusal -----------------------------------------------------
mkrepo
git -C "$R" switch -q main
echo m > "$R/m.txt"
cn -m "$MSGF" --add m.txt
eq "default branch (origin/HEAD) is refused with exit 3" "$RC" 3
expect "  tells you to branch first" "$OUT" "default branch 'main'.*(create|switch|branch)"
eq "  nothing was staged" "$(git -C "$R" status --porcelain)" "?? m.txt"
SETHEAD=0 mkrepo
git -C "$R" switch -q main
echo m > "$R/m.txt"
cn -m "$MSGF" --add m.txt
eq "default branch is refused when origin/HEAD is unset (falls back to main)" "$RC" 3
BASEBR=master SETHEAD=0 mkrepo
echo m > "$R/m.txt"
git -C "$R" switch -q master
cn -m "$MSGF" --add m.txt
eq "default branch master is refused too (origin/HEAD unset)" "$RC" 3
git -C "$R" switch -q feature/synthetic
cn -m "$MSGF" --add m.txt
eq "  while a feature branch is fine there" "$RC" 0

# ---- failing git pre-commit hook ------------------------------------------------
mkrepo
mkdir -p "$R/.git/hooks"
printf '#!/bin/sh\necho "pre-commit: synthetic failure" >&2\nexit 1\n' > "$R/.git/hooks/pre-commit"
chmod +x "$R/.git/hooks/pre-commit"
echo h > "$R/h.txt"
before=$(git -C "$R" rev-parse HEAD)
cn -m "$MSGF" -n "$NOTEF" --add h.txt --push
if [ "$RC" -ne 0 ]; then ok "failing git pre-commit hook exits non-zero (rc=$RC)"; else bad "hook failure exit" "rc=0"; fi
expect "  hook output is passed through" "$OUT" "pre-commit: synthetic failure"
expect "  says the commit failed and nothing was pushed" "$OUT" "commit-notes: commit failed; nothing pushed"
eq "  no commit was made" "$(git -C "$R" rev-parse HEAD)" "$before"
eq "  no note was added" "$(git -C "$R" notes list | wc -l | tr -d ' ')" "0"
eq "  nothing was pushed" "$(git --git-dir="$O" branch --list feature/synthetic | wc -l | tr -d ' ')" "0"
reject "  push was never attempted" "$OUT" "git push"

# ---- Claude Code hooks are run, not bypassed ------------------------------------
mkdir -p "$WORK/hooks-block-commit" "$WORK/hooks-block-push"
printf '#!/bin/bash\ncat > "%s/commit-hook.stdin"\necho "blocked by stub pre-commit-checks" >&2\nexit 2\n' "$WORK" > "$WORK/hooks-block-commit/pre-commit-checks.sh"
printf '#!/bin/bash\ncat > "%s/push-hook.stdin"\necho "blocked by stub guard-pr-state" >&2\nexit 2\n' "$WORK" > "$WORK/hooks-block-push/guard-pr-state.sh"
mkrepo
echo c > "$R/c.txt"
before=$(git -C "$R" rev-parse HEAD)
OUT=$(cd "$R" && COMMIT_NOTES_HOOKS_DIR="$WORK/hooks-block-commit" "$CN" -m "$MSGF" --add c.txt --push 2>&1); RC=$?
eq "a blocking pre-commit-checks.sh hook stops the run (exit 2)" "$RC" 2
expect "  its output is passed through" "$OUT" "blocked by stub pre-commit-checks"
expect "  and the failure line is printed" "$OUT" "commit-notes: commit failed; nothing pushed"
eq "  no commit was made" "$(git -C "$R" rev-parse HEAD)" "$before"
expect "  the hook got the stdin the harness would send" "$(cat "$WORK/commit-hook.stdin")" '"command":"git commit"'

mkrepo
echo p > "$R/p.txt"
OUT=$(cd "$R" && COMMIT_NOTES_HOOKS_DIR="$WORK/hooks-block-push" "$CN" -m "$MSGF" --add p.txt --push 2>&1); RC=$?
eq "a blocking guard-pr-state.sh hook stops the push (exit 2)" "$RC" 2
expect "  its output is passed through" "$OUT" "blocked by stub guard-pr-state"
eq "  the commit exists locally" "$(git -C "$R" log -1 --format=%s)" "msg$NEXT"
eq "  nothing reached origin" "$(git --git-dir="$O" branch --list feature/synthetic | wc -l | tr -d ' ')" "0"
expect "  the hook got the push command on stdin" "$(cat "$WORK/push-hook.stdin")" '"command":"git push"'

if [ -n "$REAL_HOOKS" ] && [ -f "$REAL_HOOKS/pre-commit-checks.sh" ]; then
  mkrepo
  echo q > "$R/q.txt"
  OUT=$(cd "$R" && COMMIT_NOTES_HOOKS_DIR="$REAL_HOOKS" "$CN" -m "$MSGF" --add q.txt 2>&1); RC=$?
  eq "the real pre-commit-checks.sh lets a plain repo commit" "$RC" 0

  # The real hook runs `git add -u` after formatting, which sweeps every modified
  # tracked file into the index. Stub ruff rewrites a.txt (an --add path) and
  # stub pytest passes; the hook sees a pyproject.toml, so it takes the Python path.
  mkdir -p "$WORK/stubbin"
  printf '#!/bin/sh\n[ "$1" = format ] && echo formatted >> a.txt\nexit 0\n' > "$WORK/stubbin/ruff"
  printf '#!/bin/sh\nexit 0\n' > "$WORK/stubbin/pytest"
  chmod +x "$WORK/stubbin/ruff" "$WORK/stubbin/pytest"
  mkrepo
  echo '[project]' > "$R/pyproject.toml"; echo a0 > "$R/a.txt"; echo b0 > "$R/b.txt"
  git -C "$R" add pyproject.toml a.txt b.txt; git -C "$R" commit -q -m "py project"
  echo a1 >> "$R/a.txt"; echo b1 >> "$R/b.txt"
  OUT=$(cd "$R" && PATH="$WORK/stubbin:$PATH" COMMIT_NOTES_HOOKS_DIR="$REAL_HOOKS" "$CN" -m "$MSGF" --add a.txt 2>&1); RC=$?
  eq "real hook sweeping b.txt with git add -u: exit 0" "$RC" 0
  eq "  only the --add path is in the commit" "$(git -C "$R" show --name-only --format= HEAD)" "a.txt"
  eq "  b.txt is still modified in the work tree, unstaged" "$(git -C "$R" status --porcelain)" " M b.txt"
  eq "  b.txt content in the work tree is untouched" "$(cat "$R/b.txt")" "$(printf 'b0\nb1')"
  expect "  warns the hook changed the staged content of b.txt and that it was restored" "$OUT" "commit-notes: WARNING: pre-commit hook changed the staged content of b\.txt, not in --add; restored it"
  reject "  does not warn about a.txt" "$OUT" "staged content of a\.txt"
  eq "  the formatter's rewrite of a.txt is in the commit" "$(git -C "$R" show HEAD:a.txt)" "$(printf 'a0\na1\nformatted')"
  expect "  prints the stat again after the hook" "$OUT" "staged changes \(after the pre-commit hook\):"
  expect "  the add line printed is the literal-pathspec form actually run" "$OUT" "^\+ git --literal-pathspecs add -- a\.txt$"
  eq "  the post-hook stat names only the committed file" "$(printf '%s\n' "$OUT" | sed -n '/after the pre-commit hook/,/^+ git commit/p' | grep -c ' | ')" "1"
fi

# A hook that stages everything and then blocks must not leave the sweep behind.
mkdir -p "$WORK/hooks-sweep-block"
printf '#!/bin/bash\ncat >/dev/null\ngit add -u\necho "stub: blocked after sweeping" >&2\nexit 2\n' > "$WORK/hooks-sweep-block/pre-commit-checks.sh"
mkrepo
echo a0 > "$R/a.txt"; echo b0 > "$R/b.txt"; git -C "$R" add a.txt b.txt; git -C "$R" commit -q -m "two files"
echo a1 >> "$R/a.txt"; echo b1 >> "$R/b.txt"
before=$(git -C "$R" rev-parse HEAD)
OUT=$(cd "$R" && COMMIT_NOTES_HOOKS_DIR="$WORK/hooks-sweep-block" "$CN" -m "$MSGF" --add a.txt 2>&1); RC=$?
eq "a hook that sweeps then blocks: exit 2" "$RC" 2
eq "  no commit was made" "$(git -C "$R" rev-parse HEAD)" "$before"
eq "  the index holds only the --add path again" "$(git -C "$R" diff --cached --name-only)" "a.txt"
expect "  warns about b.txt" "$OUT" "WARNING: pre-commit hook changed the staged content of b\.txt, not in --add; restored it"

# Without --add, anything the hook stages beyond the pre-staged set is unstaged too.
mkdir -p "$WORK/hooks-sweep"
printf '#!/bin/bash\ncat >/dev/null\ngit add -u\nexit 0\n' > "$WORK/hooks-sweep/pre-commit-checks.sh"
mkrepo
echo a0 > "$R/a.txt"; echo b0 > "$R/b.txt"; git -C "$R" add a.txt b.txt; git -C "$R" commit -q -m "two files"
echo a1 >> "$R/a.txt"; echo b1 >> "$R/b.txt"; git -C "$R" add a.txt
OUT=$(cd "$R" && COMMIT_NOTES_HOOKS_DIR="$WORK/hooks-sweep" "$CN" -m "$MSGF" 2>&1); RC=$?
eq "no --add, hook sweeps b.txt: exit 0" "$RC" 0
eq "  only the pre-staged a.txt is committed" "$(git -C "$R" show --name-only --format= HEAD)" "a.txt"
expect "  warns about b.txt" "$OUT" "WARNING: pre-commit hook changed the staged content of b\.txt, not in --add; restored it"

# --add naming a directory or glob covers what the hook stages inside it.
mkrepo
mkdir "$R/d"; echo x0 > "$R/d/x.txt"; echo y0 > "$R/d/y.txt"; echo o0 > "$R/o.txt"
git -C "$R" add d o.txt; git -C "$R" commit -q -m "dir"
echo x1 >> "$R/d/x.txt"; echo y1 >> "$R/d/y.txt"; echo o1 >> "$R/o.txt"
OUT=$(cd "$R/d" && COMMIT_NOTES_HOOKS_DIR="$WORK/hooks-sweep" "$CN" -m "$MSGF" --add x.txt 2>&1); RC=$?
eq "run from a subdirectory with a relative --add: exit 0" "$RC" 0
eq "  only d/x.txt is committed (repo-root paths unstaged correctly)" "$(git -C "$R" show --name-only --format= HEAD)" "d/x.txt"
expect "  warns about d/y.txt" "$OUT" "staged content of d/y\.txt, not in --add"
expect "  warns about o.txt" "$OUT" "staged content of o\.txt, not in --add"
eq "  the swept files are still modified in the work tree" "$(git -C "$R" status --porcelain | tr '\n' ',')" " M d/y.txt, M o.txt,"
mkrepo
mkdir "$R/d"; echo x0 > "$R/d/x.txt"; echo y0 > "$R/d/y.txt"
git -C "$R" add d; git -C "$R" commit -q -m "dir"
echo x1 >> "$R/d/x.txt"; echo y1 >> "$R/d/y.txt"
OUT=$(cd "$R" && COMMIT_NOTES_HOOKS_DIR="$WORK/hooks-sweep" "$CN" -m "$MSGF" --add d 2>&1); RC=$?
eq "--add of a directory: files the hook restages inside it stay" "$(git -C "$R" show --name-only --format= HEAD | tr '\n' ',')" "d/x.txt,d/y.txt,"
reject "  and draw no warning" "$OUT" "WARNING: pre-commit hook changed"

# A path that was already (partly) staged before the hook: `git add -u` adds the
# rest of its unstaged hunks, which the name-only comparison could not see.
mkrepo
seq 1 10 > "$R/b.txt"; echo a0 > "$R/a.txt"; git -C "$R" add b.txt a.txt; git -C "$R" commit -q -m "ten lines"
sed '1s/.*/L1x/' "$R/b.txt" > "$WORK/b-line1.txt"
cp "$WORK/b-line1.txt" "$R/b.txt"; git -C "$R" add b.txt                       # stage only line 1
sed '10s/.*/SECRET/' "$WORK/b-line1.txt" > "$R/b.txt"                           # unstaged edit on line 10
echo a1 >> "$R/a.txt"
OUT=$(cd "$R" && COMMIT_NOTES_HOOKS_DIR="$WORK/hooks-sweep" "$CN" -m "$MSGF" --add a.txt 2>&1); RC=$?
eq "partly staged b.txt, hook sweeps its other hunk: exit 0" "$RC" 0
reject "  the unstaged SECRET edit is not in the commit" "$(git -C "$R" show HEAD:b.txt)" "SECRET"
eq "  the staged line-1 change is in the commit" "$(git -C "$R" show HEAD:b.txt | head -1)" "L1x"
expect "  warns b.txt was changed by the hook and restored" "$OUT" "commit-notes: WARNING: pre-commit hook changed the staged content of b\.txt, not in --add; restored it"
expect "  the work tree b.txt still has SECRET" "$(cat "$R/b.txt")" "^SECRET$"
eq "  only the SECRET edit is left unstaged" "$(git -C "$R" diff -U0 b.txt | grep -c '^+SECRET')" "1"
eq "  nothing else is left staged" "$(git -C "$R" diff --cached --name-only)" ""

# No --add: a file staged whole, then edited again, must not gain the new edit.
mkrepo
echo c0 > "$R/c.txt"; echo d0 > "$R/d.txt"; git -C "$R" add c.txt d.txt; git -C "$R" commit -q -m "c and d"
echo c1 >> "$R/c.txt"; git -C "$R" add c.txt
echo d1 >> "$R/d.txt"                                                           # unstaged only
echo SECRET >> "$R/c.txt"                                                       # unstaged on top of the staged c.txt
OUT=$(cd "$R" && COMMIT_NOTES_HOOKS_DIR="$WORK/hooks-sweep" "$CN" -m "$MSGF" 2>&1); RC=$?
eq "no --add, pre-staged c.txt edited again, d.txt unstaged: exit 0" "$RC" 0
eq "  only c.txt is committed" "$(git -C "$R" show --name-only --format= HEAD)" "c.txt"
eq "  and c.txt is the staged content (c1), not the later edit" "$(git -C "$R" show HEAD:c.txt)" "$(printf 'c0\nc1')"
expect "  warns about c.txt" "$OUT" "staged content of c\.txt, not in --add; restored it"
expect "  warns about d.txt" "$OUT" "staged content of d\.txt, not in --add; restored it"
eq "  the work tree keeps both unstaged edits" "$(git -C "$R" status --porcelain | tr '\n' ',')" " M c.txt, M d.txt,"
# A file staged whole and unchanged since is not touched by the hook and needs no warning.
mkrepo
echo c0 > "$R/c.txt"; echo d0 > "$R/d.txt"; git -C "$R" add c.txt d.txt; git -C "$R" commit -q -m "c and d"
echo c1 >> "$R/c.txt"; git -C "$R" add c.txt; echo d1 >> "$R/d.txt"
OUT=$(cd "$R" && COMMIT_NOTES_HOOKS_DIR="$WORK/hooks-sweep" "$CN" -m "$MSGF" 2>&1); RC=$?
eq "no --add, c.txt staged whole, d.txt unstaged: exit 0" "$RC" 0
eq "  only c.txt is committed, d.txt is not" "$(git -C "$R" show --name-only --format= HEAD)" "c.txt"
reject "  no warning for c.txt" "$OUT" "staged content of c\.txt"

# An index with unmerged paths cannot be snapshotted: refuse before committing.
mkrepo
echo A > "$R/x.txt"; git -C "$R" add x.txt; git -C "$R" commit -q -m "x on feature"
git -C "$R" switch -q -c other main; echo B > "$R/x.txt"; git -C "$R" add x.txt; git -C "$R" commit -q -m "x on other"
git -C "$R" switch -q feature/synthetic; git -C "$R" merge -q other >/dev/null 2>&1
before=$(git -C "$R" rev-parse HEAD)
OUT=$(cd "$R" && COMMIT_NOTES_HOOKS_DIR="$WORK/hooks-sweep" "$CN" -m "$MSGF" 2>&1); RC=$?
eq "unmerged index: exit 3" "$RC" 3
expect "  says the index cannot be snapshotted" "$OUT" "cannot snapshot the index"
eq "  no commit was made" "$(git -C "$R" rev-parse HEAD)" "$before"

# --add paths are literal: glob characters in a name must not pull in siblings.
mkrepo
echo i0 > "$R/i.txt"; echo x0 > "$R/[id].txt"; git -C "$R" add i.txt '[id].txt'; git -C "$R" commit -q -m "bracket"
echo i1 >> "$R/i.txt"; echo x1 >> "$R/[id].txt"
cn -m "$MSGF" --add '[id].txt'
eq "--add of a bracket-named file: exit 0" "$RC" 0
eq "  only that file is committed, not the glob sibling i.txt" "$(git -C "$R" show --name-only --format= HEAD)" "[id].txt"
eq "  i.txt is still unstaged" "$(git -C "$R" status --porcelain)" " M i.txt"
mkrepo
echo i0 > "$R/i.txt"; git -C "$R" add i.txt; git -C "$R" commit -q -m "i"; echo i1 >> "$R/i.txt"
cn -m "$MSGF" --add '[id].txt'
eq "--add of a glob that only matches other files: exit 3" "$RC" 3
expect "  says it matches nothing" "$OUT" "'\[id\]\.txt' matches nothing"
eq "  nothing was staged" "$(git -C "$R" diff --cached --name-only)" ""

# Changes already in the index ride along with --add; name them.
mkrepo
echo p > "$R/pre.txt"; git -C "$R" add pre.txt; echo a > "$R/a.txt"
cn -m "$MSGF" --add a.txt
eq "--add with an already-staged other path: exit 0" "$RC" 0
expect "  warns that pre.txt was already staged and not in --add" "$OUT" "WARNING: 'pre\.txt' was already staged and is not in --add; it will be committed too"
reject "  no such warning for the --add path" "$OUT" "'a\.txt' was already staged"
mkrepo
echo a > "$R/a.txt"
cn -m "$MSGF" --add a.txt
reject "no already-staged warning when only --add paths are staged" "$OUT" "was already staged"

# ---- message file is committed verbatim -----------------------------------------
mkrepo
printf 'subject with `backticks` and $HOME\n\nbody: "double" and '"'single'"' quotes, $(echo injected), \\n, ${VAR}\n' > "$WORK/verbatim.txt"
echo v > "$R/v.txt"
cn -m "$WORK/verbatim.txt" --add v.txt
eq "message with backticks, \$ and quotes: exit 0" "$RC" 0
eq "  commit message is byte-identical to the file" "$(git -C "$R" log -1 --format=%B)" "$(cat "$WORK/verbatim.txt")"
cn -m "$WORK/missing.txt" --add v.txt
eq "missing message file exits 3" "$RC" 3
cn --add v.txt
eq "no -m exits 3" "$RC" 3
: > "$WORK/empty.txt"
cn -m "$WORK/empty.txt" --add v.txt
eq "empty message file exits 3" "$RC" 3

# ---- notes: new and pre-existing ------------------------------------------------
mkrepo
echo n > "$R/n.txt"
cn -m "$MSGF" -n "$NOTEF" --add n.txt
eq "note added: exit 0" "$RC" 0
eq "  note matches the notes file" "$(git -C "$R" notes show HEAD)" "$(cat "$NOTEF")"
reject "  no replace message for a fresh commit" "$OUT" "already has a note"

mkrepo
printf '#!/bin/sh\ngit notes add -m "preexisting note" HEAD\n' > "$R/.git/hooks/post-commit"
chmod +x "$R/.git/hooks/post-commit"
echo e > "$R/e.txt"
cn -m "$MSGF" -n "$NOTEF" --add e.txt
eq "a note already on HEAD: exit 0" "$RC" 0
expect "  says it is replacing it" "$OUT" "HEAD already has a note; replacing it"
expect "  uses notes add -f" "$OUT" "git notes add -f -F"
eq "  the note is the new text" "$(git -C "$R" notes show HEAD)" "$(cat "$NOTEF")"

# ---- notes ref is pushed only if the remote already has it ----------------------
mkrepo
git -C "$R" notes add -m "old" HEAD
git -C "$R" push -q origin refs/notes/commits
echo f > "$R/f.txt"
cn -m "$MSGF" -n "$NOTEF" --add f.txt --push
eq "push with notes when the remote has refs/notes/commits: exit 0" "$RC" 0
expect "  pushes the notes ref" "$OUT" "git push origin refs/notes/commits"
eq "  remote notes match local" "$(git --git-dir="$O" rev-parse refs/notes/commits)" "$(git -C "$R" rev-parse refs/notes/commits)"
mkrepo
echo f > "$R/f.txt"
cn -m "$MSGF" -n "$NOTEF" --add f.txt --push
eq "push with notes when the remote lacks the ref: exit 0" "$RC" 0
reject "  the notes ref is not pushed unasked" "$OUT" "^\+ git push .*refs/notes/commits"
eq "  and the remote still has none" "$(git --git-dir="$O" for-each-ref refs/notes | wc -l | tr -d ' ')" "0"
expect "  prints a NOTICE that the note stays local" "$OUT" "commit-notes: NOTICE: origin has no refs/notes/commits, so the note stays local"
expect "  with the exact command to publish it" "$OUT" "To publish it: git push origin refs/notes/commits$"
eq "  the note exists locally" "$(git -C "$R" notes show HEAD)" "$(cat "$NOTEF")"
mkrepo
echo f > "$R/f.txt"
cn -m "$MSGF" --add f.txt --push
reject "no NOTICE when no note was asked for" "$OUT" "NOTICE"

# ---- dry run changes nothing ----------------------------------------------------
mkrepo
echo d > "$R/d.txt"; echo d2 > "$R/d2.txt"
: > "$WORK/gh.log"
st_before=$(git -C "$R" status --porcelain); log_before=$(git -C "$R" log --all --format='%H %s'); idx_before=$(git -C "$R" ls-files -s)
cn -N -m "$MSGF" -n "$NOTEF" --add d.txt --push
eq "dry run exits 0" "$RC" 0
eq "  git status --porcelain unchanged" "$(git -C "$R" status --porcelain)" "$st_before"
eq "  git log unchanged" "$(git -C "$R" log --all --format='%H %s')" "$log_before"
eq "  real index unchanged" "$(git -C "$R" ls-files -s)" "$idx_before"
eq "  no notes" "$(git -C "$R" notes list | wc -l | tr -d ' ')" "0"
eq "  nothing pushed" "$(git --git-dir="$O" branch --list feature/synthetic | wc -l | tr -d ' ')" "0"
expect "  prints the staged stat it would commit" "$OUT" "d\.txt \| 1 \+"
expect "  prints the add command" "$OUT" "would run: git --literal-pathspecs add -- d\.txt"
expect "  prints the commit command" "$OUT" "would run: git commit -F "
expect "  prints the notes command" "$OUT" "would run: git notes add -F "
expect "  prints the push command" "$OUT" "would run: git push -u origin HEAD"
expect "  prints the hook it would run" "$OUT" "would run: hook pre-commit-checks\.sh"
expect "  notes the hook may stage more files" "$OUT" "the real hook may stage more files \(git add -u\)"
reject "  runs no real commands" "$OUT" "^\+ "
[ ! -s "$WORK/gh.log" ] && ok "  gh was never called" || bad "gh never called in a dry run" "$(cat "$WORK/gh.log")"
cn -N -m "$MSGF"
eq "dry run with nothing staged still refuses (exit 3)" "$RC" 3
git -C "$R" switch -q main
cn -N -m "$MSGF" --add d.txt
eq "dry run on the default branch still refuses (exit 3)" "$RC" 3

# ---- push picks the branch form from the upstream -------------------------------
# A branch cut from origin/main tracks origin/main, not origin/<branch>; a bare
# `git push` there is wrong (fails under push.default=simple, lands on main under =upstream).
mkrepo
git -C "$R" switch -q -c feat/from-main origin/main
echo t > "$R/t.txt"
main_before=$(git --git-dir="$O" rev-parse main)
OUT=$(cd "$R" && git config push.default upstream && "$CN" -m "$MSGF" --add t.txt --push 2>&1); RC=$?
eq "upstream is origin/main on another branch: exit 0" "$RC" 0
expect "  pushes with -u origin HEAD" "$OUT" "^\+ git push -u origin HEAD$"
eq "  origin/main did not move" "$(git --git-dir="$O" rev-parse main)" "$main_before"
eq "  origin has the feature branch" "$(git --git-dir="$O" rev-parse feat/from-main)" "$(git -C "$R" rev-parse HEAD)"
eq "  upstream is now the same-named branch" "$(git -C "$R" rev-parse --abbrev-ref '@{u}')" "origin/feat/from-main"
echo t2 >> "$R/t.txt"
cn -m "$MSGF" --add t.txt --push
expect "  the next push is a plain git push" "$OUT" "^\+ git push$"
mkrepo
git -C "$R" switch -q -c feat/dry origin/main
echo t > "$R/t.txt"
cn -N -m "$MSGF" --add t.txt --push
expect "dry run on a branch tracking origin/main prints push -u origin HEAD" "$OUT" "would run: git push -u origin HEAD"

# ---- PR report and warnings -----------------------------------------------------
pr_case() {  # NAME FAKE_PR  -> pushes a new commit and sets OUT/RC
  mkrepo
  echo "$1" > "$R/$1.txt"
  : > "$WORK/gh.log"
  OUT=$(cd "$R" && FAKE_PR="$2" "$CN" -m "$MSGF" --add "$1.txt" --push 2>&1); RC=$?
}
pr_case open "7\tOPEN\tmain"
eq "open PR on the default base: exit 0" "$RC" 0
expect "  prints PR #N STATE base=BASE" "$OUT" "^PR #7 OPEN base=main$"
reject "  no warning" "$OUT" "WARNING: (PR|base)"
expect "  gh pr view was asked about the branch" "$(cat "$WORK/gh.log")" "pr view feature/synthetic"

pr_case merged "7\tMERGED\tmain"
eq "merged PR: exit 0 (the push happened)" "$RC" 0
expect "  prints the state" "$OUT" "^PR #7 MERGED base=main$"
expect "  warns the PR is MERGED" "$OUT" "WARNING: PR #7 is MERGED"

pr_case closed "9\tCLOSED\tmain"
expect "closed PR: prints the state" "$OUT" "^PR #9 CLOSED base=main$"
expect "  warns the PR is CLOSED" "$OUT" "WARNING: PR #9 is CLOSED"

pr_case stacked "11\tOPEN\tfeature/base"
expect "stacked PR: prints the base" "$OUT" "^PR #11 OPEN base=feature/base$"
expect "  warns the base is not the default" "$OUT" "WARNING: base is feature/base, not main; merging this PR will not land it on main"
reject "  open PR gets no state warning" "$OUT" "WARNING: PR #11 is"

SETHEAD=0 mkrepo
echo u > "$R/u.txt"
OUT=$(cd "$R" && GH="$WORK/does-not-exist-gh" "$CN" -m "$MSGF" --add u.txt --push 2>&1); RC=$?
eq "gh unavailable: push still succeeds" "$RC" 0
expect "  says PR state was not checked" "$OUT" "gh not available; PR state not checked"

# ---- untracked warning ----------------------------------------------------------
mkrepo
echo s > "$R/staged.txt"; echo l > "$R/left-behind.txt"; mkdir "$R/dir"; echo i > "$R/dir/inner.txt"
cn -m "$MSGF" --add staged.txt
expect "untracked files outside the staged set are warned about" "$OUT" "WARNING: untracked files are NOT part of this commit"
expect "  lists the loose file" "$OUT" "^  left-behind\.txt$"
expect "  lists files in untracked directories" "$OUT" "^  dir/inner\.txt$"
mkrepo
echo s > "$R/staged.txt"
cn -m "$MSGF" --add staged.txt
reject "no warning when nothing is left untracked" "$OUT" "WARNING"

# ---- usage ----------------------------------------------------------------------
mkrepo
cn --bogus
eq "unknown flag exits 3" "$RC" 3
cn -m "$MSGF" --add
eq "--add with no path exits 3" "$RC" 3
cn -m "$MSGF" --add --
eq "--add -- with no path exits 3" "$RC" 3
echo d > "$R/-dash.txt"; echo o > "$R/other.txt"
cn -m "$MSGF" --add -dash.txt
eq "a path starting with '-' without -- is not taken as a path (exit 3)" "$RC" 3
cn -m "$MSGF" --add other.txt -- -dash.txt
eq "--add PATH -- -PATH stages both: exit 0" "$RC" 0
eq "  both are in the commit" "$(git -C "$R" show --name-only --format= HEAD | sort | tr '\n' ',')" "-dash.txt,other.txt,"
mkrepo
echo d > "$R/-dash.txt"
cn -m "$MSGF" --add -- -dash.txt
eq "--add -- -PATH alone: exit 0" "$RC" 0
eq "  commits the dash path" "$(git -C "$R" show --name-only --format= HEAD)" "-dash.txt"
OUT=$(cd "$WORK" && "$CN" -m "$MSGF" 2>&1); RC=$?
eq "outside a git work tree exits 3" "$RC" 3
cn --help
eq "--help exits 0" "$RC" 0
expect "  and shows usage" "$OUT" "Usage:"

echo
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" = 0 ]
