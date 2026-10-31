#!/bin/bash
#
# Tests for pr-approve. `gh` is replaced through the GH env var by a stub that serves
# synthetic JSON, logs every call, and copies each --input payload it is handed (no network,
# nothing is approved). Fixture world: repo acme/repo, viewer "me", PR author "dev".
#
# Usage: bin/tests/pr-approve.sh        (exit 1 if any case fails)

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
APPROVE="$HERE/../pr-approve"
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

# Stub gh. $STUB_DIR holds view-<N>.json (absent = not found; view-<N>.2.json is served from
# the second `pr view N` on, the re-read after the approval) and receives calls.log and
# payload-<n>.json copies of each POSTed review. STUB_REVIEW_COMMIT sets the commit_id of the
# review it "creates"; STUB_POST_422=1 makes the POST fail like a rejected commit_id;
# STUB_GET_FAIL=1 makes the re-read of the reviews fail. The re-read returns every review as
# login<TAB>id<TAB>state<TAB>commit (what the --jq prints), from several reviewers.
STUB="$WORK/gh"
cat > "$STUB" <<'EOS'
#!/bin/bash
D="$STUB_DIR"
echo "$*" >> "$D/calls.log"
if [ -n "${STUB_FAIL:-}" ] && [[ "$*" == *"$STUB_FAIL"* ]]; then echo "gh: HTTP 502 boom" >&2; exit 1; fi
arg_after() { local flag="$1"; shift; while [ $# -gt 0 ]; do [ "$1" = "$flag" ] && { echo "$2"; return; }; shift; done; }
case "$1 $2" in
  "repo view") echo "acme/repo" ;;
  "api user") echo "me" ;;
  "pr view")
    f="$D/view-$3.json"
    [ "$(grep -c "^pr view $3 " "$D/calls.log")" -lt 2 ] || [ ! -f "$D/view-$3.2.json" ] || f="$D/view-$3.2.json"
    if [ -f "$f" ]; then cat "$f"; else echo "GraphQL: Could not resolve to a pull request with the number of $3." >&2; exit 1; fi ;;
  "api repos/acme/repo/pulls/7/reviews")
    if [ "$(arg_after --method "$@")" = POST ]; then
      if [ -n "${STUB_POST_422:-}" ]; then
        echo '{"message":"Unprocessable Entity","errors":["commit_id is not part of the pull request"]}'
        echo "gh: Unprocessable Entity (HTTP 422)" >&2; exit 1
      fi
      n=$(grep -c -- '--method POST' "$D/calls.log")
      cp "$(arg_after --input "$@")" "$D/payload-$n.json"
      echo '{"id":777,"html_url":"https://example.invalid/acme/repo/pull/7#pullrequestreview-777"}'
    else
      [ -z "${STUB_GET_FAIL:-}" ] || { echo "gh: HTTP 500 reread boom" >&2; exit 1; }
      printf 'other\t401\tAPPROVED\t%s\n' "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
      printf 'me\t501\tCOMMENTED\t%s\n' "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      printf 'me\t777\tAPPROVED\t%s\n' "${STUB_REVIEW_COMMIT:-abcdef1234567890abcdef1234567890abcdef12}"
      printf 'other\t888\tCHANGES_REQUESTED\t%s\n' "cccccccccccccccccccccccccccccccccccccccc"
    fi ;;
  *) echo "unexpected gh call: $*" >&2; exit 99 ;;
esac
EOS
chmod +x "$STUB"

ok()  { PASS=$((PASS + 1)); echo "ok    $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL  $1"; echo "      got: $2"; }
expect() { if printf '%s\n' "$2" | grep -Eq -- "$3"; then ok "$1"; else bad "$1 (wanted /$3/)" "$2"; fi; }
reject() { if printf '%s\n' "$2" | grep -Eq -- "$3"; then bad "$1 (did not want /$3/)" "$2"; else ok "$1"; fi; }
rc_is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (wanted exit $3)" "exit $2"; fi; }

HEAD=abcdef1234567890abcdef1234567890abcdef12
new_case() {  # NAME [state] [isDraft] [author] [head]
  STUB_DIR="$WORK/$1"; mkdir -p "$STUB_DIR"; export STUB_DIR
  printf '{"state":"%s","isDraft":%s,"headRefOid":"%s","author":{"login":"%s"},"reviewDecision":"REVIEW_REQUIRED"}\n' \
    "${2:-OPEN}" "${3:-false}" "${5:-$HEAD}" "${4:-dev}" > "$STUB_DIR/view-7.json"
}
approve() {  # args... -> OUT (stdout+stderr), RC
  OUT=$(cd "$WORK" && GH="$STUB" "$APPROVE" "$@" 2>&1); RC=$?
}
calls() { cat "$STUB_DIR/calls.log" 2>/dev/null; }
no_review() { reject "$1" "$(calls)" 'method POST'; }
payload() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]], end="")' "$STUB_DIR/payload-1.json" "$1"; }

# ---- the happy path ----------------------------------------------------------------
new_case match
approve 7 --sha abcdef1234567890abcdef1234567890abcdef12 -R acme/repo
rc_is "matching sha: exit 0" "$RC" 0
expect "  POSTs the review to the reviews API from a payload file" "$(calls)" '^api repos/acme/repo/pulls/7/reviews --method POST --input [^ ]+$'
expect "  payload event is APPROVE" "$(payload event)" '^APPROVE$'
if [ "$(payload commit_id)" = "$HEAD" ]; then ok "  payload pins commit_id to the full verified head"; else bad "  payload commit_id" "$(payload commit_id)"; fi
expect "  default body names the reviewed sha7" "$(payload body)" '^Approved after review at abcdef1: no critical or high findings\.$'
reject "  no gh pr review (it cannot pin a commit)" "$(calls)" '^pr review'
if calls | grep -E '^api .*--method POST' | tr ' ' '\n' | grep -q '^@'; then bad "  no argument starts with @" "$(calls)"; else ok "  no argument starts with @"; fi
expect "  prints the viewer's latest review (not another reviewer's)" "$OUT" 'review 777 state APPROVED commit abcdef1'
reject "  and nothing from the other reviewers' rows" "$OUT" 'review (401|888)'
expect "  re-read uses the reviews API" "$(calls)" '^api repos/acme/repo/pulls/7/reviews --paginate'

new_case prefix
approve 7 --sha abcdef1 -R acme/repo
rc_is "7-char prefix matches: exit 0" "$RC" 0
expect "  approval made" "$(calls)" 'method POST'
new_case prefix_upper
approve 7 --sha ABCDEF1 -R acme/repo
rc_is "upper-case prefix matches: exit 0" "$RC" 0

new_case bodyfile
printf 'LGTM, ship it.\n' > "$WORK/my-body.md"
approve 7 --sha abcdef1 -R acme/repo --body-file "$WORK/my-body.md"
rc_is "--body-file: exit 0" "$RC" 0
expect "  the file's text is what gh received" "$(payload body)" '^LGTM, ship it\.$'

new_case norepo
approve 7 --sha abcdef1
rc_is "no -R: repo from gh repo view, exit 0" "$RC" 0
expect "  asked gh repo view" "$(calls)" '^repo view'
new_case prefix_pins_full_head
approve 7 --sha abcdef1 -R acme/repo
if [ "$(payload commit_id)" = "$HEAD" ]; then ok "7-char --sha still pins the 40-char head"; else bad "7-char --sha pin" "$(payload commit_id)"; fi

# ---- refusals ----------------------------------------------------------------------
new_case moved "OPEN" false dev 1234567890abcdef1234567890abcdef12345678
approve 7 --sha abcdef1 -R acme/repo
rc_is "head moved: exit 3" "$RC" 3
expect "  prints both shas" "$OUT" 'head moved since review: abcdef1 -> 1234567; re-review'
no_review "  no review call"

new_case closed CLOSED
approve 7 --sha abcdef1 -R acme/repo
rc_is "closed PR: exit 3" "$RC" 3
expect "  says why" "$OUT" 'CLOSED, not OPEN'
no_review "  no review call"

new_case merged MERGED
approve 7 --sha abcdef1 -R acme/repo
rc_is "merged PR: exit 3" "$RC" 3
no_review "  no review call"

new_case draft OPEN true
approve 7 --sha abcdef1 -R acme/repo
rc_is "draft PR: exit 3" "$RC" 3
expect "  says why" "$OUT" 'draft'
no_review "  no review call"

new_case selfauthored OPEN false me
approve 7 --sha abcdef1 -R acme/repo
rc_is "viewer is the author: exit 3" "$RC" 3
expect "  says self-approval is rejected" "$OUT" 'self-approval'
no_review "  no review call"

new_case landed_elsewhere
OUT=$(cd "$WORK" && STUB_REVIEW_COMMIT=9999999999999999999999999999999999999999 GH="$STUB" "$APPROVE" 7 --sha abcdef1 -R acme/repo 2>&1); RC=$?
rc_is "approval landed on another commit: exit 3" "$RC" 3
expect "  says an approval exists and to dismiss it by hand" "$OUT" 'approval EXISTS on 9999999, not the reviewed abcdef1.*dismiss review 777 by hand'

new_case head_moves_during_approval
printf '{"state":"OPEN","isDraft":false,"headRefOid":"%s","author":{"login":"dev"},"reviewDecision":"REVIEW_REQUIRED"}\n' \
  1234567890abcdef1234567890abcdef12345678 > "$STUB_DIR/view-7.2.json"
approve 7 --sha abcdef1 -R acme/repo
rc_is "head changes between the POST and the re-read: exit 3" "$RC" 3
expect "  warns the approval is on the old head and the PR moved" "$OUT" 'WARN: the approval is recorded on abcdef1 but the PR head moved to 1234567 \(on repos without "dismiss stale approvals" it may still count toward merging\)'
expect "  the approval was in fact POSTed" "$(calls)" '--method POST'

new_case head_reread_fails
printf 'not json\n' > "$STUB_DIR/view-7.2.json"
approve 7 --sha abcdef1 -R acme/repo
rc_is "PR head re-read fails after the approval: exit 2" "$RC" 2
expect "  says approved, but" "$OUT" 'approved, but re-reading the PR head failed'

new_case rejected_commit
OUT=$(cd "$WORK" && STUB_POST_422=1 GH="$STUB" "$APPROVE" 7 --sha abcdef1 -R acme/repo 2>&1); RC=$?
rc_is "GitHub rejects the pinned commit (422): refused, exit 3" "$RC" 3
expect "  carries the API message" "$OUT" 'refused: GitHub rejected the review on abcdef1.*commit_id is not part of the pull request'
reject "  and never re-reads or claims an approval" "$(calls)$OUT" 'paginate|^approved '

new_case reread_fails
OUT=$(cd "$WORK" && STUB_GET_FAIL=1 GH="$STUB" "$APPROVE" 7 --sha abcdef1 -R acme/repo 2>&1); RC=$?
rc_is "re-read fails after the approval was posted: exit 2" "$RC" 2
expect "  says approved, but" "$OUT" 'approved, but re-reading the reviews failed.*reread boom'
expect "  the approval was in fact POSTed" "$(calls)" '--method POST'

# ---- dry run -----------------------------------------------------------------------
new_case dry
approve 7 --sha abcdef1 -R acme/repo -n
rc_is "-n: exit 0" "$RC" 0
expect "  says what it would do" "$OUT" 'DRY RUN.*Would approve acme/repo#7 at abcdef1 as me.*commit_id=abcdef1234567890abcdef1234567890abcdef12'
no_review "  no review call"
reject "  no reviews re-read either" "$(calls)" '^api repos/'

new_case dry_moved "OPEN" false dev 1234567890abcdef1234567890abcdef12345678
approve 7 --sha abcdef1 -R acme/repo -n
rc_is "-n still refuses a moved head: exit 3" "$RC" 3

# ---- usage and failures ------------------------------------------------------------
new_case nosha
approve 7 -R acme/repo
rc_is "missing --sha: exit 2" "$RC" 2
expect "  names --sha" "$OUT" '\-\-sha'
[ -z "$(calls)" ] && ok "  no gh call made" || bad "  no gh call made" "$(calls)"

new_case shortsha
approve 7 --sha abc12 -R acme/repo
rc_is "--sha shorter than 7: exit 2" "$RC" 2
approve 7 --sha zzzzzzz -R acme/repo
rc_is "--sha not hex: exit 2" "$RC" 2
approve seven --sha abcdef1 -R acme/repo
rc_is "non-numeric PR: exit 2" "$RC" 2

new_case nobodyfile
approve 7 --sha abcdef1 -R acme/repo --body-file "$WORK/missing.md"
rc_is "unreadable --body-file: exit 2" "$RC" 2
no_review "  no review call"

new_case notfound
approve 99 --sha abcdef1 -R acme/repo
rc_is "PR not found: exit 1" "$RC" 1

new_case ghfail
OUT=$(cd "$WORK" && STUB_FAIL="pr view" GH="$STUB" "$APPROVE" 7 --sha abcdef1 -R acme/repo 2>&1); RC=$?
rc_is "gh failure reading the PR: exit 2" "$RC" 2
OUT=$(cd "$WORK" && STUB_FAIL="--method POST" GH="$STUB" "$APPROVE" 7 --sha abcdef1 -R acme/repo 2>&1); RC=$?
rc_is "gh failure approving (not a 422): exit 2" "$RC" 2
expect "  says so" "$OUT" 'approving failed.*HTTP 502 boom'
OUT=$(cd "$WORK" && STUB_FAIL="api user" GH="$STUB" "$APPROVE" 7 --sha abcdef1 -R acme/repo 2>&1); RC=$?
rc_is "gh failure reading the viewer: exit 2" "$RC" 2

echo
echo "pr-approve: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
