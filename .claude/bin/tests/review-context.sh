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

# ---- --diff: numbered diff ----------------------------------------------------------
# verify_numbers REPO: reads a numbered diff on stdin and checks, for every `N| +text` and
# `N|  text` line, that line N of the file on disk is exactly that text. Prints "checked K"
# (K numbered lines) or the first mismatch.
verify_numbers() {
  python3 -c '
import re, sys
repo = sys.argv[1]
path, checked = None, 0
for row in sys.stdin.read().split("\n"):
    h = re.match(r"^=== (.+?) \(\+\d+ -\d+", row)
    if h:
        path = h.group(1); continue
    m = re.match(r"^(\d+)\| ([+ ])(.*)$", row)
    if not m:
        continue
    real = open(repo + "/" + path, "rb").read().decode().split("\n")
    n, text = int(m.group(1)), m.group(3)
    if n > len(real) or real[n - 1].rstrip("\r") != text:
        print("MISMATCH %s:%d diff=%r file=%r" % (path, n, text, real[n - 1] if n <= len(real) else None)); sys.exit(0)
    checked += 1
print("checked %d" % checked)
' "$1"
}

N="$WORK/numrepo"
git init -q -b master "$N"
seq 1 30 | sed 's/^/line /' > "$N/m.txt"
echo gone > "$N/del.txt"; echo wt-gone > "$N/wtdel.txt"
seq 1 10 | sed 's/^/orig /' > "$N/ren_old.txt"
printf '\0\1\2base' > "$N/bin.dat"
printf 'one\ntwo\nthree' > "$N/nonl.txt"
printf 'c1\r\nc2\r\nc3\r\n' > "$N/crlf.txt"
seq 1 12 | sed 's/^/s /' > "$N/s.txt"
echo x > "$N/at.txt"
commit "$N" "base"
git -C "$N" checkout -q -b feature
awk 'NR==3{print "THREE changed"; next} NR==12{next} {print} NR==25{print "added after 25 a"; print "added after 25 b"}' \
  "$N/m.txt" > "$N/m.new" && mv "$N/m.new" "$N/m.txt"
git -C "$N" rm -q del.txt
git -C "$N" mv ren_old.txt ren_new.txt
awk 'NR==5{print "orig five edited"; next} {print}' "$N/ren_new.txt" > "$N/r.new" && mv "$N/r.new" "$N/ren_new.txt"
printf '\0\1\2changed' > "$N/bin.dat"
printf 'one\ntwo\nthree CHANGED' > "$N/nonl.txt"
printf 'c1\r\nc2 edited\r\nc3\r\n' > "$N/crlf.txt"
printf 'x\n@@ -1 +1 @@\n' > "$N/at.txt"
echo "brand new" > "$N/n.txt"
commit "$N" "feature work"
awk 'NR==2{print "s two staged"; next} {print}' "$N/s.txt" > "$N/s.new" && mv "$N/s.new" "$N/s.txt"
git -C "$N" add s.txt                                          # staged edit of line 2
awk 'NR==9{print "s nine unstaged"; next} {print}' "$N/s.txt" > "$N/s.new" && mv "$N/s.new" "$N/s.txt"  # unstaged edit of line 9
printf 'u1\nu2\nu3\n' > "$N/u.txt"                             # untracked
echo sp > "$N/sp ace.txt"                                      # untracked, space in name
rm "$N/wtdel.txt"                                              # tracked file deleted in the worktree only

DIFF_OUT=$("$RC" -C "$N" --diff); RCODE=$?
check    "diff: exit 0" "0" "$RCODE"
lacks    "diff: prints only the diff (no report header)" "$DIFF_OUT" "REPO:"
lacks    "diff: no defect-classes checklist" "$DIFF_OUT" "DEFECT CLASSES"
contains "diff: file list order is git's (sorted)" "$DIFF_OUT" "=== at.txt (+1 -0) ==="
check    "diff: every numbered line equals the file's line" "checked 52" "$(printf '%s\n' "$DIFF_OUT" | verify_numbers "$N")"

M_EXPECT='=== m.txt (+3 -2) ===
1|  line 1
2|  line 2
    -| -line 3
3| +THREE changed
4|  line 4
5|  line 5
6|  line 6
9|  line 9
10|  line 10
11|  line 11
    -| -line 12
12|  line 13
13|  line 14
14|  line 15
22|  line 23
23|  line 24
24|  line 25
25| +added after 25 a
26| +added after 25 b
27|  line 26
28|  line 27
29|  line 28'
check "diff: modified file, 3 hunks, exact numbering" "$M_EXPECT" "$("$RC" -C "$N" --diff m.txt)"
check "diff: new file committed on branch" $'=== n.txt (+1 -0, new file) ===\n1| +brand new' "$("$RC" -C "$N" --diff n.txt)"
check "diff: deleted file (committed on branch)" $'=== del.txt (+0 -1, deleted) ===\n    -| -gone' "$("$RC" -C "$N" --diff del.txt)"
check "diff: file deleted only in the worktree" $'=== wtdel.txt (+0 -1, deleted) ===\n    -| -wt-gone' "$("$RC" -C "$N" --diff wtdel.txt)"
REN='=== ren_new.txt (+1 -1, renamed from ren_old.txt) ===
2|  orig 2
3|  orig 3
4|  orig 4
    -| -orig 5
5| +orig five edited
6|  orig 6
7|  orig 7
8|  orig 8'
check "diff: renamed file, header names the old path" "$REN" "$("$RC" -C "$N" --diff ren_new.txt)"
check "diff: rename matched by its OLD path too" "$REN" "$("$RC" -C "$N" --diff ren_old.txt)"
check "diff: binary file is one line" "bin.dat: binary file changed" "$("$RC" -C "$N" --diff bin.dat)"
NONL='=== nonl.txt (+1 -1) ===
1|  one
2|  two
    -| -three
    \| \ No newline at end of file
3| +three CHANGED
    \| \ No newline at end of file'
check "diff: no-newline markers kept, unnumbered" "$NONL" "$("$RC" -C "$N" --diff nonl.txt)"
check "diff: untracked file rendered as all-added" $'=== u.txt (+3 -0, new file) ===\n1| +u1\n2| +u2\n3| +u3' "$("$RC" -C "$N" --diff u.txt)"
check "diff: untracked file with a space in its name" $'=== sp ace.txt (+1 -0, new file) ===\n1| +sp' "$("$RC" -C "$N" --diff "sp ace.txt")"
S_OUT=$("$RC" -C "$N" --diff s.txt)
contains "diff: staged edit present"   "$S_OUT" $'    -| -s 2\n2| +s two staged'
contains "diff: unstaged edit present" "$S_OUT" $'    -| -s 9\n9| +s nine unstaged'
check    "diff: staged+unstaged mix is one section" "1" "$(printf '%s\n' "$S_OUT" | grep -c '^=== s.txt')"
CRLF_OUT=$("$RC" -C "$N" --diff crlf.txt)
check    "diff: CRLF file renders without CR, numbers right" $'=== crlf.txt (+1 -1) ===\n1|  c1\n    -| -c2\n2| +c2 edited\n3|  c3' "$CRLF_OUT"
check    "diff: CRLF output has no carriage return" "0" "$(printf '%s' "$CRLF_OUT" | grep -c $'\r')"
check "diff: @@ inside file content is content, not a hunk header" $'=== at.txt (+1 -0) ===\n1|  x\n2| +@@ -1 +1 @@' "$("$RC" -C "$N" --diff at.txt)"

# FILE filter, several files, ./ prefix, and errors
TWO=$("$RC" -C "$N" --diff n.txt ./u.txt)
check "diff: two FILE args" "2" "$(printf '%s\n' "$TWO" | grep -c '^===')"
lacks "diff: other files excluded" "$TWO" "m.txt"
"$RC" -C "$N" --diff no-such.txt >/dev/null 2>"$WORK/err"; RCODE=$?
check    "diff: unknown path exits 3" "3" "$RCODE"
contains "diff: unknown path named on stderr" "$(cat "$WORK/err")" "not a changed path"
"$RC" -C "$N" --diff n.txt no-such.txt >/dev/null 2>&1; check "diff: one unknown among known still exits 3" "3" "$?"
"$RC" -C "$N" --diff a.txt-not-here >/dev/null 2>&1; check "diff: unchanged-but-missing path exits 3" "3" "$?"
"$RC" -C "$N" n.txt >/dev/null 2>&1; check "FILE without --diff exits 2" "2" "$?"
"$RC" -C "$N" -U 2 --files-only >/dev/null 2>&1; check "-U without --diff exits 2" "2" "$?"
"$RC" -C "$N" --diff --files-only >/dev/null 2>&1; check "--diff with --files-only exits 2" "2" "$?"
"$RC" -C "$N" --diff -U x >/dev/null 2>&1; check "-U non-numeric exits 2" "2" "$?"

# -U N
U0=$("$RC" -C "$N" --diff -U 0 m.txt)
check "diff -U 0: changes only, numbers still exact" $'=== m.txt (+3 -2) ===\n    -| -line 3\n3| +THREE changed\n    -| -line 12\n25| +added after 25 a\n26| +added after 25 b' "$U0"
check "diff -U 0: only added lines carry numbers" "checked 3" "$(printf '%s\n' "$U0" | verify_numbers "$N")"
U5=$("$RC" -C "$N" --diff -U5 m.txt)
contains "diff -U5: wider context than the default" "$U5" $'7|  line 7\n8|  line 8'
lacks    "diff -U3 default lacks that context" "$("$RC" -C "$N" --diff m.txt)" "7|  line 7"
check    "diff -U5: numbers still equal the file's lines" "checked 28" "$(printf '%s\n' "$U5" | verify_numbers "$N")"

# invocation forms: from a subdirectory, via a symlink, via a relative path
mkdir -p "$N/sub"
check "diff: from a subdirectory, paths stay root-relative" $'=== n.txt (+1 -0, new file) ===\n1| +brand new' "$("$RC" -C "$N/sub" --diff n.txt)"
ln -s "$RC" "$WORK/rc-link"
check "diff: through a symlink" $'=== n.txt (+1 -0, new file) ===\n1| +brand new' "$("$WORK/rc-link" -C "$N" --diff n.txt)"
check "diff: via a relative path" $'=== n.txt (+1 -0, new file) ===\n1| +brand new' "$(cd "$HERE/.." && ./review-context -C "$N" --diff n.txt)"

# --base: the diff starts at the merge base, committed changes included; unresolved base falls back to HEAD
BASE_OUT=$("$RC" -C "$N" --base master --diff)
check "diff: --base master equals the default" "$DIFF_OUT" "$BASE_OUT"
HEAD_OUT=$("$RC" -C "$N" --base no-such-branch --diff 2>/dev/null)
contains "diff: unresolved base still shows uncommitted work" "$HEAD_OUT" "=== s.txt"
lacks    "diff: unresolved base does not show committed branch work" "$HEAD_OUT" "n.txt"

# clean tree
check "diff: clean tree prints (no changes)" "(no changes)" "$("$RC" -C "$C" --diff)"

# the parser itself, on diffs git would not produce here (hand-written, synthetic)
ND="$HERE/../lib/numbered_diff.py"
check "parser: hunk header without counts (@@ -1 +1 @@)" $'=== one.txt (+1 -1) ===\n    -| -old\n1| +new' \
  "$(printf 'diff --git a/one.txt b/one.txt\n--- a/one.txt\n+++ b/one.txt\n@@ -1 +1 @@\n-old\n+new\n' | python3 "$ND")"
check "parser: hunk header with function context, start line 40" $'=== f.py (+1 -0) ===\n40|  def f():\n41| +    pass' \
  "$(printf 'diff --git a/f.py b/f.py\n--- a/f.py\n+++ b/f.py\n@@ -40,1 +40,2 @@ class K:\n def f():\n+    pass\n' | python3 "$ND")"
check "parser: a deleted line that looks like a file header is content" $'=== d.txt (+0 -2) ===\n    -| --- a/x\n    -| -++ b/y' \
  "$(printf 'diff --git a/d.txt b/d.txt\n--- a/d.txt\n+++ b/d.txt\n@@ -1,2 +0,0 @@\n--- a/x\n-++ b/y\n' | python3 "$ND")"
check "parser: path with spaces (TAB-suffixed ---/+++ rows)" $'=== my file.txt (+1 -0) ===\n1| +hi' \
  "$(printf 'diff --git a/my file.txt b/my file.txt\n--- a/my file.txt\t\n+++ b/my file.txt\t\n@@ -0,0 +1 @@\n+hi\n' | python3 "$ND")"
check "parser: mode-only change with spaces in the path has no lines" $'=== my file.txt (+0 -0) ===' \
  "$(printf 'diff --git a/my file.txt b/my file.txt\nold mode 100644\nnew mode 100755\n' | python3 "$ND")"
check "parser: C-quoted path is unquoted" $'=== a\tb.txt (+1 -0, new file) ===\n1| +z' \
  "$(printf 'diff --git "a/a\\tb.txt" "b/a\\tb.txt"\nnew file mode 100644\n--- /dev/null\n+++ "b/a\\tb.txt"\n@@ -0,0 +1 @@\n+z\n' | python3 "$ND")"
check "parser: pure rename (100%) has a header and no lines" $'=== new.txt (+0 -0, renamed from old.txt) ===' \
  "$(printf 'diff --git a/old.txt b/new.txt\nsimilarity index 100%%\nrename from old.txt\nrename to new.txt\n' | python3 "$ND")"
check "parser: empty input" "(no changes)" "$(printf '' | python3 "$ND")"
check "parser: an empty new file (no ---/+++ rows) is a new file" $'=== empty.txt (+0 -0, new file) ===' \
  "$(printf 'diff --git a/empty.txt b/empty.txt\nnew file mode 100644\nindex 0000000..e69de29\n' | python3 "$ND")"
check "parser: an empty deleted file is deleted" $'=== empty.txt (+0 -0, deleted) ===' \
  "$(printf 'diff --git a/empty.txt b/empty.txt\ndeleted file mode 100644\nindex e69de29..0000000\n' | python3 "$ND")"
check "parser: an empty new file with a space in its name" $'=== my empty.txt (+0 -0, new file) ===' \
  "$(printf 'diff --git a/my empty.txt b/my empty.txt\nnew file mode 100644\nindex 0000000..e69de29\n' | python3 "$ND")"
check "parser: empty new and deleted files beside a normal one, --only filters them" $'=== gone.txt (+0 -0, deleted) ===' \
  "$(printf 'diff --git a/gone.txt b/gone.txt\ndeleted file mode 100644\nindex e69de29..0000000\ndiff --git a/e.txt b/e.txt\nnew file mode 100644\nindex 0000000..e69de29\ndiff --git a/k.txt b/k.txt\n--- a/k.txt\n+++ b/k.txt\n@@ -1 +1 @@\n-a\n+b\n' | python3 "$ND" --only gone.txt)"
check "parser: a mode-only change is still modified, not new" $'=== m.sh (+0 -0) ===' \
  "$(printf 'diff --git a/m.sh b/m.sh\nold mode 100644\nnew mode 100755\n' | python3 "$ND")"
check "parser: U+2028 inside a line does not shift later line numbers" $'=== u.txt (+2 -0, new file) ===\n1| +a\xe2\x80\xa8b\n2| +c' \
  "$(printf 'diff --git a/u.txt b/u.txt\nnew file mode 100644\n--- /dev/null\n+++ b/u.txt\n@@ -0,0 +1,2 @@\n+a\xe2\x80\xa8b\n+c\n' | python3 "$ND")"

# defaults unchanged: the existing report still has no diff section
lacks "report without --diff has no numbered lines" "$(DEFECT_CLASSES="$DEF" "$RC" -C "$N")" "| +brand new"

echo
echo "review-context tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
