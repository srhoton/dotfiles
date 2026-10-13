#!/bin/bash
#
# Tests for review-context. Builds throwaway git repos (synthetic content only)
# with a master + feature branch, a staged change, an unstaged change, an
# untracked file and deleted files, then asserts on the exact output.
#
# Usage: bin/tests/review-context.sh        (exit 1 if any case fails)

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
RC="$HERE/../review-context"
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

# Isolate from the user's git config (signing, hooks) and pin identity.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

check() { # NAME EXPECTED ACTUAL
  if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "ok   - $1"
  else FAIL=$((FAIL + 1)); echo "FAIL - $1"; echo "  expected: $(printf '%s' "$2" | head -c 600 | tr '\n' '|')"
       echo "  actual:   $(printf '%s' "$3" | head -c 600 | tr '\n' '|')"; fi
}
contains() { # NAME HAYSTACK NEEDLE
  case "$2" in *"$3"*) PASS=$((PASS + 1)); echo "ok   - $1" ;;
    *) FAIL=$((FAIL + 1)); echo "FAIL - $1 (missing: $3)"; echo "  in: $(printf '%s' "$2" | head -c 800 | tr '\n' '|')" ;; esac
}
lacks() { # NAME HAYSTACK NEEDLE
  case "$2" in *"$3"*) FAIL=$((FAIL + 1)); echo "FAIL - $1 (unexpected: $3)" ;;
    *) PASS=$((PASS + 1)); echo "ok   - $1" ;; esac
}

commit() { git -C "$1" add -A && git -C "$1" commit -q -m "$2"; }

# ---- main fixture ---------------------------------------------------------------
R="$WORK/repo"
git init -q -b master "$R"
mkdir -p "$R/sub"
for f in a.txt b.txt c.txt d.txt g.txt sub/x.txt; do echo "base $f" > "$R/$f"; done
commit "$R" "base commit"
MASTER_SHORT=$(git -C "$R" rev-parse --short master)

git -C "$R" checkout -q -b feature
echo "branch change" >> "$R/a.txt"          # committed on branch (and again, unstaged, below)
echo "new on branch" > "$R/e.txt"            # added on branch
git -C "$R" rm -q d.txt                      # deleted on branch
commit "$R" "feature work one"
echo "more" > "$R/e2.txt"; commit "$R" "feature work two"

echo "staged" >> "$R/b.txt";   git -C "$R" add b.txt     # staged only
echo "unstaged" >> "$R/c.txt"                            # unstaged only
echo "again" >> "$R/a.txt"                                # also committed -> dedup
echo "untracked" > "$R/f.txt"                             # untracked
echo "spaced" > "$R/h i.txt"                              # untracked, space in name
rm "$R/g.txt"                                             # deleted in worktree (unstaged)

EXPECTED_FILES=$'a.txt\nb.txt\nc.txt\ne.txt\ne2.txt\nf.txt\nh i.txt'

# 1. --files-only exact output, deduped, deleted excluded, nothing else
OUT=$("$RC" -C "$R" --files-only); RCODE=$?
check "files-only exact list" "$EXPECTED_FILES" "$OUT"
check "files-only exit 0" "0" "$RCODE"

# 2. from a subdirectory, paths stay repo-root relative
OUT=$("$RC" -C "$R/sub" --files-only)
check "files-only from subdir is root-relative" "$EXPECTED_FILES" "$OUT"

# 3. full report
DEF="$WORK/defects.md"; echo "SYNTHETIC-DEFECT-MARKER" > "$DEF"
FULL=$(DEFECT_CLASSES="$DEF" "$RC" -C "$R")
contains "report: repo root"          "$FULL" "REPO:       $(cd "$R" && pwd -P)"
contains "report: branch"             "$FULL" "BRANCH:     feature"
contains "report: base detected as master" "$FULL" "BASE:       master"
contains "report: merge-base sha"     "$FULL" "MERGE-BASE: $MASTER_SHORT"
contains "report: branch log newest"  "$FULL" "feature work two"
contains "report: branch log older"   "$FULL" "feature work one"
lacks    "report: base commit not in branch log" "$FULL" "base commit"
contains "report: branch stat names deleted-on-branch file" "$FULL" "d.txt"
contains "report: staged stat"        "$FULL" "--- staged ---"$'\n'" b.txt"
contains "report: untracked listed"   "$FULL" "h i.txt"
contains "report: changed count"      "$FULL" "=== CHANGED FILES (7) ==="
contains "report: deleted note"       "$FULL" "=== DELETED (2, not in the list above) ==="$'\n'"d.txt"$'\n'"g.txt"
contains "report: defect marker"      "$FULL" "SYNTHETIC-DEFECT-MARKER"
CHG=${FULL#*=== CHANGED FILES}; CHG=${CHG%%=== DELETED*}
lacks    "report: deleted files not under CHANGED FILES" "$CHG" "g.txt"

# 4. --no-defects
NOD=$(DEFECT_CLASSES="$DEF" "$RC" -C "$R" --no-defects)
lacks    "no-defects omits checklist" "$NOD" "SYNTHETIC-DEFECT-MARKER"
MISS=$(DEFECT_CLASSES="$WORK/nope.md" "$RC" -C "$R")
contains "missing defect file warns" "$MISS" "WARN: defect-classes file not readable"

# 5. explicit --base, from a feature branch
OUT=$("$RC" -C "$R" --base master --files-only)
check "--base master same list" "$EXPECTED_FILES" "$OUT"

# 6. unresolvable base: warn on stderr, still list working-tree changes, exit 0
ERR=$("$RC" -C "$R" --base no-such-branch --files-only 2>&1 >/dev/null); RCODE=$?
OUT=$("$RC" -C "$R" --base no-such-branch --files-only 2>/dev/null)
contains "bad base warns on stderr" "$ERR" "WARN base branch 'no-such-branch' not found"
check "bad base lists only uncommitted changes" $'a.txt\nb.txt\nc.txt\nf.txt\nh i.txt' "$OUT"
check "bad base exit 0" "0" "$RCODE"

# ---- base detection -------------------------------------------------------------
# main instead of master
M="$WORK/mainrepo"
git init -q -b main "$M"; echo 1 > "$M/k.txt"; commit "$M" "init"
git -C "$M" checkout -q -b topic; echo 2 > "$M/k2.txt"; commit "$M" "topic"
OUT=$("$RC" -C "$M" --no-defects)
contains "falls back to main"  "$OUT" "BASE:       main"
check    "main-based files-only" "k2.txt" "$("$RC" -C "$M" --files-only)"

# origin/HEAD wins over master; a stale local branch of the same name is ignored
O="$WORK/originrepo"
git init -q -b master "$O"; echo 1 > "$O/k.txt"; commit "$O" "init"
git -C "$O" branch develop                                       # local develop stays at init
git -C "$O" checkout -q -b topic; echo 2 > "$O/k2.txt"; commit "$O" "topic one"
git -C "$O" update-ref refs/remotes/origin/develop HEAD          # origin/develop is ahead of local develop
echo 3 > "$O/k3.txt"; commit "$O" "topic two"
git -C "$O" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop
OUT=$("$RC" -C "$O" --no-defects)
contains "origin/HEAD detected, origin ref preferred" "$OUT" "BASE:       origin/develop"
contains "origin/HEAD merge-base shown" "$OUT" "MERGE-BASE: $(git -C "$O" rev-parse --short HEAD~1)"
check    "origin/HEAD base limits files" "k3.txt" "$("$RC" -C "$O" --files-only)"

# base advanced after the branch point: three-dot diff must not report base-only files
T="$WORK/threedot"
git init -q -b master "$T"; echo 1 > "$T/k.txt"; commit "$T" "init"
git -C "$T" checkout -q -b topic; echo 2 > "$T/k2.txt"; commit "$T" "topic work"
git -C "$T" checkout -q master; echo 9 > "$T/m-only.txt"; commit "$T" "master moved on"
git -C "$T" checkout -q topic
OUT=$("$RC" -C "$T" --no-defects)
lacks    "base-only file not reported anywhere" "$OUT" "m-only.txt"
lacks    "base-only commit not in branch log" "$OUT" "master moved on"
check    "three-dot files-only" "k2.txt" "$("$RC" -C "$T" --files-only)"

# stale local master: detected default uses origin/master, explicit --base uses local
S="$WORK/stalerepo"
git init -q -b master "$S"; echo 1 > "$S/k.txt"; commit "$S" "init"
git -C "$S" checkout -q -b topic; echo 2 > "$S/k2.txt"; commit "$S" "topic one"
git -C "$S" update-ref refs/remotes/origin/master topic          # origin is ahead of local master
git -C "$S" checkout -q -b topic2; echo 3 > "$S/k3.txt"; commit "$S" "topic two"
check "default prefers origin/master (stale local ignored)" "k3.txt" "$("$RC" -C "$S" --files-only)"
check "explicit --base master is literal" $'k2.txt\nk3.txt' "$("$RC" -C "$S" --base master --files-only)"

# clean tree
C="$WORK/clean"
git init -q -b master "$C"; echo 1 > "$C/k.txt"; commit "$C" "init"
OUT=$("$RC" -C "$C" --no-defects); RCODE=$?
contains "clean tree shows none" "$OUT" "=== CHANGED FILES (0) ==="$'\n'"(none)"
check "clean tree files-only is empty" "" "$("$RC" -C "$C" --files-only)"
check "clean tree exit 0" "0" "$RCODE"

# ---- errors ---------------------------------------------------------------------
NG="$WORK/not-a-repo"; mkdir -p "$NG"
GIT_CEILING_DIRECTORIES="$WORK" "$RC" -C "$NG" >/dev/null 2>&1; check "not a git repo exits 2" "2" "$?"
GIT_CEILING_DIRECTORIES="$WORK" "$RC" -C "$NG" --files-only >/dev/null 2>&1; check "not a git repo exits 2 (files-only)" "2" "$?"
"$RC" -C "$WORK/missing-dir" >/dev/null 2>&1; check "missing -C dir exits 2" "2" "$?"
"$RC" --bogus >/dev/null 2>&1; check "unknown flag exits 2" "2" "$?"
contains "-h prints header" "$("$RC" -h)" "review-context [--base BRANCH]"

echo
echo "review-context tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
