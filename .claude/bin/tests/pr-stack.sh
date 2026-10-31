#!/bin/bash
#
# Tests for pr-stack. `gh` is replaced through the GH env var by a stub that serves
# synthetic JSON from a fixture directory and logs every call (no network, nothing is
# mutated). Fixture world: repo acme/repo, default branch main.
#
# Usage: bin/tests/pr-stack.sh        (exit 1 if any case fails)

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
STACK="$HERE/../pr-stack"
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

# Stub gh. $STUB_DIR holds: repo.json, list-author.json, view-<N>.json (absent = not found;
# view-<N>.2.json is served from the second `pr view N` on), list-head-<branch>.json
# (absent = []), branch-<branch>.json (absent = 404, i.e. the branch is gone), and receives
# calls.log. STUB_FAIL=<word> makes any call whose arguments contain the word fail;
# STUB_EDIT_FAIL=<N> makes `pr edit N` fail; STUB_PATH restores PATH for the stub itself.
STUB="$WORK/gh"
cat > "$STUB" <<'EOS'
#!/bin/bash
[ -z "${STUB_PATH:-}" ] || PATH="$STUB_PATH"
D="$STUB_DIR"
echo "$*" >> "$D/calls.log"
if [ -n "${STUB_FAIL:-}" ] && [[ "$*" == *"$STUB_FAIL"* ]]; then echo "gh: HTTP 502 boom" >&2; exit 1; fi
arg_after() { local flag="$1"; shift; while [ $# -gt 0 ]; do [ "$1" = "$flag" ] && { echo "$2"; return; }; shift; done; }
case "$1 $2" in
  "repo view") cat "$D/repo.json" ;;
  "pr list")
    head=$(arg_after --head "$@")
    if [ -n "$head" ]; then
      f="$D/list-head-$(printf '%s' "$head" | tr '/' '_').json"; if [ -f "$f" ]; then cat "$f"; else echo '[]'; fi
    else
      cat "$D/list-author.json"
    fi ;;
  "pr view")
    f="$D/view-$3.json"
    [ "$(grep -c "^pr view $3 " "$D/calls.log")" -lt 2 ] || [ ! -f "$D/view-$3.2.json" ] || f="$D/view-$3.2.json"
    if [ -f "$f" ]; then cat "$f"; else echo "GraphQL: Could not resolve to a pull request with the number of $3." >&2; exit 1; fi ;;
  "pr edit")
    [ "${STUB_EDIT_FAIL:-}" != "$3" ] || { echo "gh: edit refused" >&2; exit 1; }
    echo "https://example.invalid/acme/repo/pull/$3" ;;
  "api repos/acme/repo/branches/"*)
    f="$D/branch-$(printf '%s' "${2#repos/acme/repo/branches/}" | tr '/' '_').json"
    if [ -f "$f" ]; then cat "$f"; else echo '{"message":"Branch not found"}'; echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi ;;
  *) echo "unexpected gh call: $*" >&2; exit 99 ;;
esac
EOS
chmod +x "$STUB"

ok()  { PASS=$((PASS + 1)); echo "ok    $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL  $1"; echo "      got: $2"; }
expect() { if printf '%s\n' "$2" | grep -Eq -- "$3"; then ok "$1"; else bad "$1 (wanted /$3/)" "$2"; fi; }
reject() { if printf '%s\n' "$2" | grep -Eq -- "$3"; then bad "$1 (did not want /$3/)" "$2"; else ok "$1"; fi; }
rc_is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (wanted exit $3)" "exit $2"; fi; }

PO=7777777eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee   # a merged parent's head commit

new_world() {  # NAME -> fresh STUB_DIR with the repo and an empty author list
  STUB_DIR="$WORK/$1"; mkdir -p "$STUB_DIR"; export STUB_DIR
  echo '{"nameWithOwner":"acme/repo","defaultBranchRef":{"name":"main"}}' > "$STUB_DIR/repo.json"
  echo '[]' > "$STUB_DIR/list-author.json"
}
add_pr() {  # NUM STATE BASE HEAD-BRANCH SHA [isDraft]
  printf '{"number":%s,"state":"%s","isDraft":%s,"baseRefName":"%s","headRefName":"%s","headRefOid":"%s","mergedAt":null,"url":"https://example.invalid/acme/repo/pull/%s"}\n' \
    "$1" "$2" "${6:-false}" "$3" "$4" "$5" "$1" > "$STUB_DIR/view-$1.json"
}
entry() {  # BRANCH NUM STATE BASE OID CROSS TS -> one `pr list --head` object
  local m=null c=null
  [ "$3" = MERGED ] && m="\"$7\""
  [ "$3" = CLOSED ] && c="\"$7\""
  printf '{"number":%s,"state":"%s","mergedAt":%s,"closedAt":%s,"headRefName":"%s","headRefOid":"%s","baseRefName":"%s","isCrossRepository":%s}' \
    "$2" "$3" "$m" "$c" "$1" "$5" "$4" "$6"
}
set_heads() {  # BRANCH ENTRY... -> list-head-BRANCH.json
  local b="$1"; shift; local IFS=,
  printf '[%s]\n' "$*" > "$STUB_DIR/list-head-$(printf '%s' "$b" | tr '/' '_').json"
}
add_parent() {  # BRANCH NUM STATE [BASE] [OID] [TS]
  set_heads "$1" "$(entry "$1" "$2" "$3" "${4:-main}" "${5:-$PO}" false "${6:-2026-01-01T00:00:00Z}")"
}
add_branch() {  # BRANCH SHA [PROTECTED=false]: the branch still exists on the remote at SHA
  printf '{"commit":{"sha":"%s"},"protected":%s}\n' "$2" "${3:-false}" > "$STUB_DIR/branch-$(printf '%s' "$1" | tr '/' '_').json"
}
stack() {  # args... -> stdout+stderr; sets RC. Run outside any git repo.
  OUT=$(cd "$WORK" && GH="$STUB" "$STACK" "$@" 2>&1); RC=$?
}
calls() { cat "$STUB_DIR/calls.log" 2>/dev/null; }

S1=1111111aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
S2=2222222bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
S3=3333333ccccccccccccccccccccccccccccccccc

# ---- verdicts ------------------------------------------------------------------
new_world base
add_pr 10 OPEN main feat-10 $S1
stack 10 -R acme/repo
expect "base is the default branch: OK, no parent" "$OUT" '^#10 +OPEN +base=main head=1111111 parent=none -> OK'
rc_is "  exit 0" "$RC" 0
reject "  no parent lookup made for a default-branch PR" "$(calls)" 'pr list.*--head'

new_world open_parent
add_pr 11 OPEN feat-10 feat-11 $S2
add_parent feat-10 10 OPEN
stack 11 -R acme/repo
expect "parent open: OK with the parent shown" "$OUT" '^#11 +OPEN +base=feat-10 head=2222222 parent=#10\(OPEN\) -> OK$'
rc_is "  exit 0" "$RC" 0

new_world merged_parent
add_pr 12 OPEN feat-10 feat-12 $S2
add_parent feat-10 10 MERGED
stack 12 -R acme/repo
expect "parent merged, branch gone: NEEDS-RETARGET" "$OUT" 'parent=#10\(MERGED\) -> NEEDS-RETARGET'
rc_is "  exit 3" "$RC" 3

new_world merged_parent_at_head
add_pr 12 OPEN feat-10 feat-12 $S2
add_parent feat-10 10 MERGED
add_branch feat-10 $PO
stack 12 -R acme/repo
expect "parent merged, branch still at the merged head: NEEDS-RETARGET" "$OUT" 'parent=#10\(MERGED\) -> NEEDS-RETARGET'

new_world closed_parent
add_pr 13 OPEN feat-10 feat-13 $S2
add_parent feat-10 10 CLOSED
stack 13 -R acme/repo
expect "parent closed without merge: PARENT-CLOSED" "$OUT" 'parent=#10\(CLOSED\) -> PARENT-CLOSED'
rc_is "  exit 3" "$RC" 3

new_world no_parent
add_pr 14 OPEN gone-branch feat-14 $S2
stack 14 -R acme/repo
expect "no PR for the base branch: NO-PARENT-PR" "$OUT" 'parent=none -> NO-PARENT-PR'
rc_is "  exit 3" "$RC" 3

new_world self_merged
add_pr 15 MERGED main feat-15 $S1
stack 15 -R acme/repo
expect "PR itself merged: MERGED" "$OUT" '^#15 +MERGED .* -> MERGED$'
rc_is "  exit 0" "$RC" 0

new_world self_closed
add_pr 16 CLOSED feat-10 feat-16 $S1
add_parent feat-10 10 MERGED
stack 16 -R acme/repo
expect "PR itself closed: CLOSED (not NEEDS-RETARGET)" "$OUT" '-> CLOSED$'
rc_is "  exit 0" "$RC" 0
reject "  and no branch lookup for it" "$(calls)" 'api repos'

new_world draft
add_pr 17 OPEN main feat-17 $S1 true
stack 17 -R acme/repo
expect "draft shown" "$OUT" '^#17 +OPEN/draft '

# ---- parent ranking ---------------------------------------------------------------
new_world rank_open_wins
add_pr 18 OPEN feat-10 feat-18 $S2
set_heads feat-10 \
  "$(entry feat-10 9 MERGED main $PO false 2026-05-01T00:00:00Z)" \
  "$(entry feat-10 5 OPEN main $PO false "")" \
  "$(entry feat-10 7 CLOSED main $PO false 2026-06-01T00:00:00Z)"
stack 18 -R acme/repo
expect "an open parent beats newer merged/closed ones" "$OUT" 'parent=#5\(OPEN\) -> OK$'

new_world rank_newest_merged
add_pr 18 OPEN feat-10 feat-18 $S2
set_heads feat-10 \
  "$(entry feat-10 9 MERGED main $PO false 2026-01-01T00:00:00Z)" \
  "$(entry feat-10 4 MERGED main $PO false 2026-03-01T00:00:00Z)"
stack 18 -R acme/repo
expect "two merged parents: the most recently merged wins, not the highest number" "$OUT" 'parent=#4\(MERGED\) -> NEEDS-RETARGET'

new_world rank_closed_newer
add_pr 18 OPEN feat-10 feat-18 $S2
set_heads feat-10 \
  "$(entry feat-10 9 MERGED main $PO false 2026-01-01T00:00:00Z)" \
  "$(entry feat-10 4 CLOSED main $PO false 2026-04-01T00:00:00Z)"
stack 18 -R acme/repo
expect "a newer closed parent is not outranked by an older merged one" "$OUT" 'parent=#4\(CLOSED\) -> PARENT-CLOSED'

new_world cross_repo_only
add_pr 18 OPEN feat-10 feat-18 $S2
set_heads feat-10 "$(entry feat-10 9 MERGED main $PO true 2026-01-01T00:00:00Z)"
stack 18 -R acme/repo
expect "a fork PR with the same head name is not a parent" "$OUT" 'parent=none -> NO-PARENT-PR'

new_world cross_repo_mixed
add_pr 18 OPEN feat-10 feat-18 $S2
set_heads feat-10 \
  "$(entry feat-10 50 OPEN main $PO true "")" \
  "$(entry feat-10 10 MERGED main $PO false 2026-01-01T00:00:00Z)"
stack 18 -R acme/repo
expect "  a newer open fork PR does not displace the same-repo parent" "$OUT" 'parent=#10\(MERGED\) -> NEEDS-RETARGET'

new_world live_base
add_pr 19 OPEN develop feat-19 $S2
add_parent develop 3 MERGED main
add_branch develop 9999999ffffffffffffffffffffffffffffffffff
stack 19 -R acme/repo --retarget
expect "merged parent but the base branch moved on: OK with a note" "$OUT" 'parent=#3\(MERGED\) -> OK  \(base is a live branch \(parent #3 merged earlier\)\)'
rc_is "  exit 0" "$RC" 0
reject "  --retarget never edits a live base" "$(calls)" 'pr edit'

# gitflow: right after a `develop -> main` release PR merges, develop's tip IS that PR's head
new_world protected_base_at_merged_head
add_pr 19 OPEN develop feat-19 $S2
add_parent develop 3 MERGED main
add_branch develop $PO true
stack 19 -R acme/repo --retarget
expect "protected base whose tip equals the merged release head: OK with a protected note" "$OUT" 'parent=#3\(MERGED\) -> OK  \(base is a protected branch \(parent #3 merged earlier\)\)'
rc_is "  exit 0" "$RC" 0
reject "  --retarget does not edit it" "$(calls)" 'pr edit'

new_world unprotected_base_at_merged_head
add_pr 19 OPEN feat-10 feat-19 $S2
add_parent feat-10 3 MERGED main
add_branch feat-10 $PO false
stack 19 -R acme/repo
expect "unprotected stack branch whose tip equals the merged head: still NEEDS-RETARGET" "$OUT" 'parent=#3\(MERGED\) -> NEEDS-RETARGET'
rc_is "  exit 3" "$RC" 3
stack 19 -R acme/repo --retarget
expect "  and --retarget moves it" "$(calls)" '^pr edit 19 -R acme/repo --base main$'

new_world retarget_walk_stops_protected
add_pr 3 OPEN feat-b feat-c $S3
add_parent feat-b 2 MERGED feat-a
add_parent feat-a 1 MERGED main $PO
add_branch feat-a $PO true
stack 3 -R acme/repo --retarget
expect "the walk stops at a protected base even at the merged head" "$OUT" '^retargeted #3: feat-b -> feat-a$'

# ---- --retarget ------------------------------------------------------------------
new_world retarget
add_pr 20 OPEN feat-10 feat-20 $S2
add_parent feat-10 10 MERGED
add_pr 21 OPEN main feat-21 $S1
add_pr 22 OPEN feat-11 feat-22 $S3
add_parent feat-11 11 OPEN
stack 20 21 22 -R acme/repo
rc_is "without --retarget: exit 3" "$RC" 3
reject "  never calls pr edit" "$(calls)" 'pr edit'
stack 20 21 22 -R acme/repo --retarget
expect "--retarget reports the retarget (parent's base is main)" "$OUT" '^retargeted #20: feat-10 -> main$'
expect "  and the rebase hint" "$OUT" '#20 may now need a rebase onto main'
rc_is "  exit 0 once every NEEDS-RETARGET was retargeted" "$RC" 0
expect "  gh pr edit 20 --base main was called" "$(calls)" '^pr edit 20 -R acme/repo --base main$'
if [ "$(calls | grep -c '^pr edit')" = 1 ]; then ok "  and only for the NEEDS-RETARGET PR"; else bad "  pr edit count" "$(calls)"; fi

# A (feat-a, open, base main) <- B (feat-b, merged into A) <- C (#3, base feat-b)
new_world retarget_stack
add_pr 3 OPEN feat-b feat-c $S3
add_parent feat-b 2 MERGED feat-a
add_parent feat-a 1 OPEN main
stack 3 -R acme/repo --retarget
expect "B merged into open A: C moves onto A, not main" "$OUT" '^retargeted #3: feat-b -> feat-a$'
expect "  gh pr edit 3 --base feat-a" "$(calls)" '^pr edit 3 -R acme/repo --base feat-a$'
rc_is "  exit 0" "$RC" 0

new_world retarget_walk_up
add_pr 3 OPEN feat-b feat-c $S3
add_parent feat-b 2 MERGED feat-a
add_parent feat-a 1 MERGED main
stack 3 -R acme/repo --retarget
expect "B and A both merged and spent: walks up to the default branch" "$OUT" '^retargeted #3: feat-b -> main$'
expect "  gh pr edit 3 --base main" "$(calls)" '^pr edit 3 -R acme/repo --base main$'

new_world retarget_walk_stops_live
add_pr 3 OPEN feat-b feat-c $S3
add_parent feat-b 2 MERGED feat-a
add_parent feat-a 1 MERGED main
add_branch feat-a 9999999ffffffffffffffffffffffffffffffffff
stack 3 -R acme/repo --retarget
expect "the walk stops at a base that is a live branch" "$OUT" '^retargeted #3: feat-b -> feat-a$'

new_world retarget_unfixable
add_pr 23 OPEN feat-10 feat-23 $S2
add_parent feat-10 10 CLOSED
stack 23 -R acme/repo --retarget
rc_is "--retarget does not hide PARENT-CLOSED: exit 3" "$RC" 3
reject "  and does not call pr edit for it" "$(calls)" 'pr edit'

new_world retarget_fail
add_pr 24 OPEN feat-10 feat-24 $S2
add_parent feat-10 10 MERGED
OUT=$(cd "$WORK" && STUB_EDIT_FAIL=24 GH="$STUB" "$STACK" 24 -R acme/repo --retarget 2>&1); RC=$?
rc_is "failed retarget: exit 2" "$RC" 2
expect "  names the failing edit" "$OUT" 'gh pr edit #24'
expect "  the report is still printed" "$OUT" '^#24 .* -> NEEDS-RETARGET'

new_world retarget_partial_json
add_pr 80 OPEN feat-10 feat-80 $S2
add_pr 81 OPEN feat-10 feat-81 $S3
add_parent feat-10 10 MERGED
OUT=$(cd "$WORK" && STUB_EDIT_FAIL=80 GH="$STUB" "$STACK" 80 81 -R acme/repo --json --retarget 2>"$WORK/err.txt"); RC=$?
rc_is "--json, one retarget fails and one succeeds: exit 2" "$RC" 2
printf '%s' "$OUT" | python3 -c '
import json, sys
d = {r["number"]: r for r in json.load(sys.stdin)}
assert d[80]["retargeted"] is False and "edit refused" in d[80]["retargetError"], d[80]
assert d[81]["retargeted"] is True and d[81]["retargetError"] is None, d[81]
' && ok "  stdout is still the JSON report with the success and the per-PR retargetError" || bad "  partial --json" "$OUT"
expect "  the failure is on stderr" "$(cat "$WORK/err.txt")" 'gh pr edit #80 --base main failed'
expect "  the PR after the failure was still retargeted" "$(calls)" '^pr edit 81 -R acme/repo --base main$'

new_world retarget_changed
add_pr 90 OPEN feat-10 feat-90 $S2
add_parent feat-10 10 MERGED
add_pr 90 OPEN main feat-90 $S2 && mv "$STUB_DIR/view-90.json" "$STUB_DIR/view-90.2.json"
add_pr 90 OPEN feat-10 feat-90 $S2
stack 90 -R acme/repo --retarget
expect "a PR whose base changed since it was read is skipped, with a message" "$OUT" 'skipped #90: it changed since it was read \(now OPEN, base main\)'
reject "  and not edited" "$(calls)" 'pr edit'
rc_is "  still exit 3 (nothing was fixed)" "$RC" 3

# ---- no args, json, errors ---------------------------------------------------------
new_world noargs
add_pr 30 OPEN main feat-30 $S1
add_pr 31 OPEN feat-30 feat-31 $S2
add_parent feat-30 30 OPEN
echo '[{"number":31},{"number":30}]' > "$STUB_DIR/list-author.json"
stack
expect "no args: lists my open PRs" "$(calls)" 'pr list -R acme/repo --author @me --state open'
if [ "$(printf '%s\n' "$OUT" | grep -c '^#3[01] ')" = 2 ] && [ "$(printf '%s\n' "$OUT" | grep '^#3' | head -1 | cut -c1-3)" = '#30' ]; then ok "  both PRs, #30 first"; else bad "  both PRs" "$OUT"; fi
rc_is "  exit 0" "$RC" 0

new_world noargs_empty
stack
expect "no args, none open: says so" "$OUT" 'no open PRs'
rc_is "  exit 0" "$RC" 0

new_world json
add_pr 40 OPEN feat-10 feat-40 $S2
add_parent feat-10 10 MERGED
add_pr 41 OPEN main feat-41 $S1
OUT=$(cd "$WORK" && GH="$STUB" "$STACK" 40 41 -R acme/repo --json 2>/dev/null); RC=$?
printf '%s' "$OUT" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert isinstance(d, list) and len(d) == 2, d
a, b = d
assert a["number"] == 40 and a["verdict"] == "NEEDS-RETARGET" and a["parent"] == {"number": 10, "state": "MERGED"}, a
assert a["baseRefName"] == "feat-10" and a["headRefName"] == "feat-40" and a["headRefOid"].startswith("2222222"), a
assert b["verdict"] == "OK" and b["parent"] is None and b["state"] == "OPEN" and b["isDraft"] is False, b
assert a["ahead"] is None and a["retargeted"] is False and a["retargetError"] is None and a["note"] is None, a
assert not any(k.startswith("_") for k in a), a
' && ok "--json: array of objects with the documented fields" || bad "--json shape" "$OUT"
rc_is "  exit 3 still signals NEEDS-RETARGET" "$RC" 3

OUT=$(cd "$WORK" && GH="$STUB" "$STACK" 40 -R acme/repo --json --retarget 2>/dev/null)
printf '%s' "$OUT" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d[0]["retargeted"] is True, d
' && ok "--json --retarget: stdout stays valid JSON and marks retargeted" || bad "--json --retarget" "$OUT"

new_world notfound
add_pr 50 OPEN main feat-50 $S1
stack 50 99 -R acme/repo
rc_is "PR not found: exit 1" "$RC" 1
expect "  names the PR" "$OUT" 'acme/repo#99 not found'
expect "  the found PR is still reported" "$OUT" '^#50 .* -> OK'

new_world ghfail
add_pr 60 OPEN main feat-60 $S1
OUT=$(cd "$WORK" && STUB_FAIL="pr view" GH="$STUB" "$STACK" 60 -R acme/repo 2>&1); RC=$?
rc_is "gh failure (not a not-found): exit 2" "$RC" 2
expect "  says what failed" "$OUT" 'HTTP 502 boom'

new_world ghfail_repo
OUT=$(cd "$WORK" && STUB_FAIL="repo view" GH="$STUB" "$STACK" 60 2>&1); RC=$?
rc_is "gh repo view failure: exit 2" "$RC" 2

new_world ghfail_branch
add_pr 61 OPEN feat-10 feat-61 $S1
add_parent feat-10 10 MERGED
OUT=$(cd "$WORK" && STUB_FAIL="api repos" GH="$STUB" "$STACK" 61 -R acme/repo 2>&1); RC=$?
rc_is "branch lookup fails with something other than 404: exit 2, not a guess" "$RC" 2
expect "  says what failed" "$OUT" 'branches/feat-10.*HTTP 502 boom'

stack abc
rc_is "non-numeric PR: usage exit 2" "$RC" 2

# ---- malformed gh responses: exit 2 (Failure), never a traceback (exit 1 = not found) --
new_world badresp
printf '{"number":70,"state":"OPEN","headRefName":"x","headRefOid":"%s"}\n' "$S1" > "$STUB_DIR/view-70.json"
stack 70 -R acme/repo
rc_is "a PR response without baseRefName: exit 2" "$RC" 2
expect "  names the missing key" "$OUT" "missing 'baseRefName'"
reject "  no traceback" "$OUT" 'Traceback'
printf '{"number":71,"state":"WEIRD","baseRefName":"main","headRefName":"x","headRefOid":"%s"}\n' "$S1" > "$STUB_DIR/view-71.json"
stack 71 -R acme/repo
rc_is "an unknown state: exit 2" "$RC" 2
printf '{"baseRefName":"main"}\n' > "$STUB_DIR/view-72.json"
stack 72 -R acme/repo
rc_is "a response with no state: exit 2" "$RC" 2
echo '[{"state":"OPEN"}]' > "$STUB_DIR/list-author.json"
stack
rc_is "an author list entry without a number: exit 2" "$RC" 2
add_pr 73 OPEN feat-10 feat-73 $S1
echo '[]' > "$STUB_DIR/list-author.json"
echo '[{"state":"MERGED","headRefName":"feat-10"}]' > "$STUB_DIR/list-head-feat-10.json"
stack 73 -R acme/repo
rc_is "a parent entry without a number: exit 2" "$RC" 2

# ---- list limits -------------------------------------------------------------------
new_world limits
add_pr 74 OPEN feat-10 feat-74 $S1
python3 -c '
import json
print(json.dumps([{"number": n, "state": "CLOSED", "mergedAt": None, "closedAt": "2026-01-01T00:00:00Z",
                   "headRefName": "feat-10", "headRefOid": "x", "baseRefName": "main", "isCrossRepository": False}
                  for n in range(1, 101)]))' > "$STUB_DIR/list-head-feat-10.json"
stack 74 -R acme/repo
expect "a parent list that returns exactly its limit warns" "$OUT" 'WARN: gh pr list --head feat-10 returned 100 results'
python3 -c 'import json; print(json.dumps([{"number": n} for n in range(1, 101)]))' > "$STUB_DIR/list-author.json"
stack
expect "an author list that returns exactly its limit warns" "$OUT" 'WARN: gh pr list --author @me returned 100 results'

# ---- local clone: ahead/behind -----------------------------------------------------
new_world clonew
mkdir -p "$WORK/remotes/acme" && git init -q --bare -b main "$WORK/remotes/acme/repo.git"
git clone -q "$WORK/remotes/acme/repo.git" "$WORK/clone" 2>/dev/null
(
  cd "$WORK/clone" && git config user.email t@example.invalid && git config user.name t \
    && git commit -q --allow-empty -m base && git push -q origin HEAD:main \
    && git checkout -q -b feat-70 && git commit -q --allow-empty -m one && git commit -q --allow-empty -m two \
    && git push -q origin feat-70 && git checkout -q main && git commit -q --allow-empty -m three && git push -q origin main
)
HEAD70=$(git -C "$WORK/clone" rev-parse feat-70)
add_pr 70 OPEN main feat-70 "$HEAD70"
OUT=$(cd "$WORK/clone" && GH="$STUB" "$STACK" 70 -R acme/repo 2>&1); RC=$?
expect "in a clone of the repo: ahead/behind vs origin/main" "$OUT" '\[ahead 2 / behind 1 origin/main\]'
rc_is "  exit 0" "$RC" 0
OUT=$(cd "$WORK/clone" && GH="$STUB" "$STACK" 70 -R acme/repo --json 2>&1)
printf '%s' "$OUT" | python3 -c '
import json, sys
d = json.load(sys.stdin)[0]
assert d["ahead"] == 2 and d["behind"] == 1, d
' && ok "  json carries ahead and behind" || bad "  json ahead/behind" "$OUT"

echo '{"nameWithOwner":"other/repo","defaultBranchRef":{"name":"main"}}' > "$STUB_DIR/repo.json"
OUT=$(cd "$WORK/clone" && GH="$STUB" "$STACK" 70 -R other/repo 2>&1)
reject "clone of a different repo: no ahead/behind" "$OUT" 'ahead'

echo '{"nameWithOwner":"acme/repo","defaultBranchRef":{"name":"main"}}' > "$STUB_DIR/repo.json"
git -C "$WORK/clone" remote set-url origin "file://$WORK/remotes/acme/repo.git"
mv "$WORK/remotes/acme/repo.git" "$WORK/remotes/acme/repo.git.moved"
OUT=$(cd "$WORK/clone" && GH="$STUB" "$STACK" 70 -R acme/repo 2>&1); RC=$?
expect "failed fetch: WARN, ahead/behind skipped" "$OUT" 'WARN: git fetch origin failed'
reject "  and nothing is shown for it" "$OUT" '\[ahead'
rc_is "  the verdict still works: exit 0" "$RC" 0

# git itself missing: ahead/behind is optional, so it warns and the verdicts still work
NOGIT="$WORK/nogit"; mkdir -p "$NOGIT"; ln -s "$(command -v python3)" "$NOGIT/python3"
REAL_PATH="$PATH"; ENV_BIN=$(command -v env)
OUT=$(cd "$WORK" && STUB_PATH="$REAL_PATH" GH="$STUB" PATH="$NOGIT" "$ENV_BIN" python3 "$STACK" 70 -R acme/repo 2>&1); RC=$?
expect "git not installed: WARN, ahead/behind skipped" "$OUT" "WARN: 'git' is not installed"
expect "  the verdict is still reported" "$OUT" '^#70 .* -> OK'
rc_is "  exit 0, not 2" "$RC" 0

echo
echo "pr-stack: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
