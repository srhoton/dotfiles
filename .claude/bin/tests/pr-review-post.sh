#!/bin/bash
#
# Tests for pr-review-post. A stub gh (selected via the GH env var) serves
# synthetic PR data and records every call and every body file it is handed, so
# nothing ever reaches GitHub. Cases cover the inline/fallback split, the dry
# run, the real-post call shapes, and the review-POST failure retry.
#
# Usage: bin/tests/pr-review-post.sh        (exit 1 if any case fails)

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
POST="$HERE/../pr-review-post"
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

check() { # NAME EXIT-STATUS-OF-CONDITION
  if [ "$2" -eq 0 ]; then PASS=$((PASS + 1)); echo "ok   $1"
  else FAIL=$((FAIL + 1)); echo "FAIL $1"; fi
}

# Stub gh: STUB_DIR holds pr.json (PR), files.json (paginated files), flags
# fail_review / fail_comment, and receives calls.log plus copies of each body.
cat > "$WORK/gh" <<'STUB'
#!/bin/bash
D="$STUB_DIR"
echo "$*" >> "$D/calls.log"
arg_after() { # FLAG ARGS... -> value after FLAG
  local flag="$1"; shift
  while [ $# -gt 0 ]; do [ "$1" = "$flag" ] && { echo "$2"; return; }; shift; done
}
case "$1 $2" in
  "api repos/o/r/pulls/7") cat "$D/pr.json" ;;
  "api repos/o/r/pulls/7/files") cat "$D/files.json" ;;
  "api repos/o/r/pulls/7/reviews")
    cp "$(arg_after --input "$@")" "$D/review-payload.$(grep -c reviews "$D/calls.log").json"
    if [ -e "$D/fail_review" ]; then echo "gh: Unprocessable Entity (HTTP 422)" >&2; exit 1; fi
    echo '{"html_url":"https://example.invalid/o/r/pull/7#pullrequestreview-1"}' ;;
  "pr comment")
    n=$(grep -c '^pr comment' "$D/calls.log")
    cp "$(arg_after --body-file "$@")" "$D/comment-$n.md"
    if [ -e "$D/fail_comment" ]; then echo "gh: comment failed" >&2; exit 1; fi
    echo "https://example.invalid/o/r/pull/7#issuecomment-$n" ;;
  *) echo "stub gh: unexpected call: $*" >&2; exit 99 ;;
esac
STUB
chmod +x "$WORK/gh"

new_case() { # NAME -> sets STUB_DIR with PR data and findings
  STUB_DIR="$WORK/$1"; mkdir -p "$STUB_DIR"; export STUB_DIR
  echo '{"head":{"sha":"abc123def456"}}' > "$STUB_DIR/pr.json"
  # Two paginated pages concatenated, as gh api --paginate prints them. Right-side lines:
  # app.ts 1 (context), 2 (added), 3 and 4 (context), 51 (context), 52 (added).
  python3 - "$STUB_DIR/files.json" <<'PY'
import json, sys
patch = ("@@ -1,3 +1,4 @@\n ctx one\n-removed\n+added two\n ctx three\n ctx four\n"
         "@@ -50,2 +51,2 @@\n ctx fifty-one\n+added fifty-two\n\\ No newline at end of file")
page1 = [{"filename": "src/app.ts", "status": "modified", "patch": patch}]
page2 = [{"filename": "src/binary.png", "status": "added"}]
open(sys.argv[1], "w").write(json.dumps(page1) + json.dumps(page2))
PY
  cat > "$STUB_DIR/findings.json" <<'JSON'
{"reviewers": "functional-reviewer + test-reviewer",
 "findings": [
  {"severity": "high", "file": "src/app.ts", "line": 2, "description": "added-line finding", "suggestion": "do the thing"},
  {"severity": "MEDIUM", "file": "./src/app.ts", "line": 3, "description": "context-line finding"},
  {"severity": "LOW", "file": "src/app.ts", "line": 20, "description": "outside any hunk | with pipe", "suggestion": "move it"}
 ]}
JSON
}

run() { GH="$WORK/gh" "$POST" "$@"; }

# py ASSERTION-EXPR FILE: python expression over `d` (parsed JSON of FILE) must be truthy
py() { python3 -c 'import json,sys; d=json.load(open(sys.argv[2])); sys.exit(0 if eval(sys.argv[1]) else 1)' "$1" "$2"; }

# --- dry run: payload split, nothing posted -----------------------------------
new_case dry
OUT=$(run 7 "$STUB_DIR/findings.json" -R o/r -n 2>&1); RC=$?
check "dry run: exit 0" $((RC))
check "dry run: states 2 inline, 1 fallback" $(echo "$OUT" | grep -qF "would post inline 2, fallback 1"; echo $?)
check "dry run: review payload printed with commit_id and RIGHT side" $(echo "$OUT" | grep -qF '"commit_id": "abc123def456"' && echo "$OUT" | grep -qF '"side": "RIGHT"'; echo $?)
check "dry run: added-line and context-line findings are inline" $(echo "$OUT" | grep -qF 'added-line finding' && echo "$OUT" | grep -qF 'context-line finding'; echo $?)
check "dry run: no review POST and no comment issued" $(! grep -qE 'reviews|^pr comment' "$STUB_DIR/calls.log"; echo $?)
check "dry run: only read-only api calls were made" $(! grep -qE -- '--method|--input|--body-file' "$STUB_DIR/calls.log"; echo $?)

# --- real post: one review + one fallback comment ------------------------------
new_case real
OUT=$(run 7 "$STUB_DIR/findings.json" -R o/r 2>&1); RC=$?
check "post: exit 0" $((RC))
check "post: summary line" $(echo "$OUT" | grep -qF "posted inline 2, fallback 1, review https://example.invalid/o/r/pull/7#pullrequestreview-1"; echo $?)
check "post: exactly one review POST with --method POST --input" $([ "$(grep -c 'reviews --method POST --input' "$STUB_DIR/calls.log")" -eq 1 ]; echo $?)
check "post: exactly one gh pr comment with -R and --body-file" $([ "$(grep -c '^pr comment 7 -R o/r --body-file' "$STUB_DIR/calls.log")" -eq 1 ]; echo $?)
P="$STUB_DIR/review-payload.1.json"
check "post: payload commit_id, default event, 2 comments" $(py "d['commit_id']=='abc123def456' and d['event']=='COMMENT' and len(d['comments'])==2" "$P"; echo $?)
check "post: inline comments target lines 2 and 3 on src/app.ts, side RIGHT" $(py "[(c['path'],c['line'],c['side']) for c in d['comments']]==[('src/app.ts',2,'RIGHT'),('src/app.ts',3,'RIGHT')]" "$P"; echo $?)
check "post: inline body has exact format with suggestion and reviewers" $(py "d['comments'][0]['body']=='**[HIGH]** \`src/app.ts:2\`\n\nadded-line finding\n\n**Suggested fix:** do the thing\n\n_Reviewed by Claude (functional-reviewer + test-reviewer)_'" "$P"; echo $?)
check "post: suggestion-less body omits the Suggested fix line" $(py "d['comments'][1]['body']=='**[MEDIUM]** \`src/app.ts:3\`\n\ncontext-line finding\n\n_Reviewed by Claude (functional-reviewer + test-reviewer)_'" "$P"; echo $?)
check "post: default review body is a one-line summary" $(py "'\n' not in d['body'] and '2 inline' in d['body']" "$P"; echo $?)
C="$STUB_DIR/comment-1.md"
check "post: fallback comment holds only the out-of-diff finding" $(grep -qF 'outside any hunk | with pipe' "$C" && grep -qF '**Suggested fix:** move it' "$C" && ! grep -qF 'added-line finding' "$C"; echo $?)

# --- event and --body-file ---------------------------------------------------
new_case event
echo "Custom review summary" > "$STUB_DIR/body.md"
run 7 "$STUB_DIR/findings.json" -R o/r --event REQUEST_CHANGES --body-file "$STUB_DIR/body.md" >/dev/null 2>&1; RC=$?
check "event/body-file: payload carries them" $([ "$RC" -eq 0 ] && py "d['event']=='REQUEST_CHANGES' and d['body'].strip()=='Custom review summary'" "$STUB_DIR/review-payload.1.json"; echo $?)

# --- bare list, default reviewers, all findings inline -------------------------
new_case bare
echo '[{"severity":"CRITICAL","file":"src/app.ts","line":52,"description":"bare list finding"}]' > "$STUB_DIR/findings.json"
OUT=$(run 7 "$STUB_DIR/findings.json" -R o/r 2>&1); RC=$?
check "bare list: inline only, no fallback comment, default reviewers" $([ "$RC" -eq 0 ] && ! grep -q '^pr comment' "$STUB_DIR/calls.log" && py "d['comments'][0]['body'].endswith('_Reviewed by Claude (functional-reviewer + code-quality-reviewer + adr-compliance-reviewer + performance-reviewer + data-side-effects-reviewer)_')" "$STUB_DIR/review-payload.1.json"; echo $?)

# --- hunk edges: removed lines and the no-newline marker are not commentable ----
new_case edges
cat > "$STUB_DIR/findings.json" <<'JSON'
[{"severity":"HIGH","file":"src/app.ts","line":4,"description":"last line of hunk one"},
 {"severity":"HIGH","file":"src/app.ts","line":5,"description":"one past hunk one"},
 {"severity":"HIGH","file":"src/app.ts","line":52,"description":"last added line"},
 {"severity":"HIGH","file":"src/app.ts","line":53,"description":"after the no-newline marker"},
 {"severity":"HIGH","file":"src/binary.png","line":1,"description":"file without a patch"}]
JSON
run 7 "$STUB_DIR/findings.json" -R o/r >/dev/null 2>&1; RC=$?
check "hunk edges: lines 4 and 52 inline" $([ "$RC" -eq 0 ] && py "[c['line'] for c in d['comments']]==[4,52]" "$STUB_DIR/review-payload.1.json"; echo $?)
check "hunk edges: line 5, line 53 and the patchless file fall back" $(grep -qF 'one past hunk one' "$STUB_DIR/comment-1.md" && grep -qF 'after the no-newline marker' "$STUB_DIR/comment-1.md" && grep -qF 'file without a patch' "$STUB_DIR/comment-1.md" && ! grep -qF 'last added line' "$STUB_DIR/comment-1.md"; echo $?)

# --- nothing in the diff: no empty review is posted ----------------------------
new_case nodiff
echo '[{"severity":"HIGH","file":"src/other.ts","line":1,"description":"not in this PR"}]' > "$STUB_DIR/findings.json"
run 7 "$STUB_DIR/findings.json" -R o/r >/dev/null 2>&1; RC=$?
check "no inline findings: comment only, no review POST" $([ "$RC" -eq 0 ] && ! grep -q reviews "$STUB_DIR/calls.log" && grep -q '^pr comment' "$STUB_DIR/calls.log"; echo $?)

# --- 422 on the review: all findings re-posted as one comment -------------------
new_case retry
touch "$STUB_DIR/fail_review"
OUT=$(run 7 "$STUB_DIR/findings.json" -R o/r 2>&1); RC=$?
check "422 retry: exit 0 and says so" $([ "$RC" -eq 0 ] && echo "$OUT" | grep -qF "re-posting all 3 finding(s)"; echo $?)
check "422 retry: one review attempt, one comment" $([ "$(grep -c 'reviews --method POST' "$STUB_DIR/calls.log")" -eq 1 ] && [ "$(grep -c '^pr comment' "$STUB_DIR/calls.log")" -eq 1 ]; echo $?)
check "422 retry: comment contains every finding" $(grep -qF 'added-line finding' "$STUB_DIR/comment-1.md" && grep -qF 'context-line finding' "$STUB_DIR/comment-1.md" && grep -qF 'outside any hunk' "$STUB_DIR/comment-1.md"; echo $?)

# --- 422 retry keeps --body-file text; a non-COMMENT event is flagged and exits 1 ---
new_case retrybody
touch "$STUB_DIR/fail_review"
echo "Please read this summary first" > "$STUB_DIR/body.md"
run 7 "$STUB_DIR/findings.json" -R o/r --body-file "$STUB_DIR/body.md" >/dev/null 2>&1; RC=$?
check "422 retry with --body-file: exit 0, comment starts with the body text" $([ "$RC" -eq 0 ] && [ "$(head -1 "$STUB_DIR/comment-1.md")" = "Please read this summary first" ] && grep -qF 'added-line finding' "$STUB_DIR/comment-1.md"; echo $?)

new_case retryevent
touch "$STUB_DIR/fail_review"
OUT=$(run 7 "$STUB_DIR/findings.json" -R o/r --event REQUEST_CHANGES 2>&1); RC=$?
check "422 retry with --event REQUEST_CHANGES: findings still posted, WARN, exit 1" $([ "$RC" -eq 1 ] && echo "$OUT" | grep -qF "WARN: review event REQUEST_CHANGES could not be applied" && [ -s "$STUB_DIR/comment-1.md" ]; echo $?)

# --- final failure exits non-zero ------------------------------------------------
new_case dead
touch "$STUB_DIR/fail_review" "$STUB_DIR/fail_comment"
run 7 "$STUB_DIR/findings.json" -R o/r >/dev/null 2>&1; RC=$?
check "review and fallback both fail: exit 1" $([ "$RC" -eq 1 ]; echo $?)

new_case fbfail
touch "$STUB_DIR/fail_comment"
OUT=$(run 7 "$STUB_DIR/findings.json" -R o/r 2>&1); RC=$?
check "review ok but fallback comment fails: exit 1" $([ "$RC" -eq 1 ]; echo $?)
check "fallback fails after review: says the inline review is already posted, with its URL" $(echo "$OUT" | grep -qF "inline review already posted (https://example.invalid/o/r/pull/7#pullrequestreview-1) - do not re-run"; echo $?)

# --- form feed inside a context line must not shift line numbers (L1) ----------------
new_case formfeed
python3 - "$STUB_DIR/files.json" <<'PY'
import json, sys
patch = "@@ -1,3 +1,3 @@\n ctx\x0cmore\n+added two\n ctx three"
open(sys.argv[1], "w").write(json.dumps([{"filename": "src/app.ts", "patch": patch}]))
PY
cat > "$STUB_DIR/findings.json" <<'JSON'
[{"severity":"HIGH","file":"src/app.ts","line":3,"description":"real last line"},
 {"severity":"HIGH","file":"src/app.ts","line":4,"description":"phantom line from form feed"}]
JSON
run 7 "$STUB_DIR/findings.json" -R o/r >/dev/null 2>&1; RC=$?
check "form feed: line 3 inline, phantom line 4 falls back" $([ "$RC" -eq 0 ] && py "[c['line'] for c in d['comments']]==[3]" "$STUB_DIR/review-payload.1.json" && grep -qF 'phantom line from form feed' "$STUB_DIR/comment-1.md"; echo $?)

# --- local checkout checks (L3): stale-HEAD warning and absolute paths ---------------
new_clone() { # NAME REMOTE-URL -> git repo at $CLONE with one commit
  CLONE="$WORK/clone-$1"; mkdir -p "$CLONE"
  git -C "$CLONE" init -q && git -C "$CLONE" remote add origin "$2" \
    && git -C "$CLONE" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
}
in_clone() { (cd "$CLONE" && run "$@"); }

new_case stale
new_clone stale https://github.com/o/r.git
OUT=$(in_clone 7 "$STUB_DIR/findings.json" -R o/r -n 2>&1 >/dev/null); RC=$?
check "clone of the PR repo, HEAD != PR head: stale-checkout WARN on stderr, still exit 0" $([ "$RC" -eq 0 ] && echo "$OUT" | grep -qF "may be from a stale checkout"; echo $?)

new_case fresh
new_clone fresh git@github.com:o/r.git
HEAD_SHA=$(git -C "$CLONE" rev-parse HEAD)
echo "{\"head\":{\"sha\":\"$HEAD_SHA\"}}" > "$STUB_DIR/pr.json"
OUT=$(in_clone 7 "$STUB_DIR/findings.json" -R o/r -n 2>&1 >/dev/null)
check "clone with HEAD == PR head: no warning" $(! echo "$OUT" | grep -qF "stale checkout"; echo $?)

for alias in "git@github-work:o/r.git" "ssh://git@ssh.github.com:443/O/R.git" "https://example.invalid/o/r/"; do
  new_case "alias-$alias"
  new_clone "alias-$(echo "$alias" | tr -c 'a-zA-Z0-9\n' _)" "$alias"
  OUT=$(in_clone 7 "$STUB_DIR/findings.json" -R o/r -n 2>&1 >/dev/null)
  check "alias remote $alias: stale-checkout WARN fires" $(echo "$OUT" | grep -qF "may be from a stale checkout"; echo $?)
done

new_case otherrepo
new_clone otherrepo https://github.com/someone/else.git
OUT=$(in_clone 7 "$STUB_DIR/findings.json" -R o/r -n 2>&1 >/dev/null)
check "clone of a different repo: no warning" $(! echo "$OUT" | grep -qF "stale checkout"; echo $?)

new_case abspath
new_clone abspath https://github.com/o/r.git
ROOT=$(git -C "$CLONE" rev-parse --show-toplevel)
cat > "$STUB_DIR/findings.json" <<JSON
[{"severity":"HIGH","file":"$ROOT/src/app.ts","line":2,"description":"absolute path finding"}]
JSON
in_clone 7 "$STUB_DIR/findings.json" -R o/r >/dev/null 2>&1; RC=$?
check "absolute finding path under the repo root: relativized and posted inline" $([ "$RC" -eq 0 ] && py "[(c['path'],c['line']) for c in d['comments']]==[('src/app.ts',2)] and '$ROOT' not in d['comments'][0]['body']" "$STUB_DIR/review-payload.1.json"; echo $?)

# --- bad input ---------------------------------------------------------------------
new_case badin
echo 'not json' > "$STUB_DIR/findings.json"
run 7 "$STUB_DIR/findings.json" -R o/r >/dev/null 2>&1; RC=$?
check "unparseable findings: exit 2, nothing fetched or posted" $([ "$RC" -eq 2 ] && [ ! -e "$STUB_DIR/calls.log" ]; echo $?)

echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
