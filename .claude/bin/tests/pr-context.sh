#!/bin/bash
#
# Tests for pr-context. `gh` is replaced through the GH env var by a stub that
# prints a synthetic GraphQL response (no GitHub call, nothing posted). Every
# fixture is invented: repo acme/repo, viewer "me", reviewers "rev"/"ci-bot".
#
# Usage: bin/tests/pr-context.sh        (exit 1 if any case fails)

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
CTX="$HERE/../pr-context"
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

# fixture NAME 'PYTHON-EXPR'  — the expression is one pr(...) call; the viewer is "me".
fixture() {
  python3 - "$WORK/$1.json" "$2" <<'PY'
import json, sys

def comment(id, login="rev", typename="User", body="please fix", created="2026-09-21T10:00:00Z"):
    return {"databaseId": id, "body": body, "createdAt": created,
            "author": {"login": login, "__typename": typename}}

def thread(id, first_id, comments, path="src/a.py", line=12, resolved=False, outdated=False):
    # comments: list of comment(...); firstComment/lastComment are the aliases the query uses.
    return {"id": id, "isResolved": resolved, "isOutdated": outdated, "path": path, "line": line,
            "firstComment": {"nodes": [{"databaseId": comments[0]["databaseId"],
                                        "author": comments[0]["author"]}]},
            "lastComment": {"nodes": [{"id": "N%d" % comments[-1]["databaseId"],
                                       "databaseId": comments[-1]["databaseId"],
                                       "author": {"login": comments[-1]["author"]["login"]}}]},
            "comments": {"totalCount": len(comments), "nodes": comments}}

def conv(id, login="rev", typename="User", body="top-level note", reactions=(),
         created="2026-09-21T10:00:00Z", edited=None):
    groups = {}
    for content, who in reactions:
        groups[content] = groups.get(content, False) or who == "me"
    return {"databaseId": id, "url": "https://example.test/c/%d" % id, "body": body,
            "createdAt": created, "lastEditedAt": edited, "isMinimized": False,
            "author": {"login": login, "__typename": typename},
            "reactionGroups": [{"content": k, "viewerHasReacted": v} for k, v in groups.items()],
            "reactions": {"nodes": [{"content": c, "createdAt": "2026-09-21T11:00:00Z",
                                     "user": {"login": w}} for c, w in reactions]}}

def run_check(name, status="COMPLETED", conclusion="SUCCESS"):
    return {"__typename": "CheckRun", "name": name, "status": status, "conclusion": conclusion}

def status_ctx(name, state):
    return {"__typename": "StatusContext", "context": name, "state": state}

def pr(threads=(), comments=(), checks=(), head="aaaaaaaaaaaa1111", mergeable="MERGEABLE",
       reviews=(), body="synthetic body", decision="auto"):
    # reviews: (id, author, state) or (id, author, state, body)
    return {
        "number": 7, "title": "Synthetic change", "url": "https://example.test/acme/repo/pull/7",
        "state": "OPEN", "isDraft": False, "baseRefName": "main", "headRefName": "feature-7",
        "headRefOid": head, "mergeable": mergeable, "mergeStateStatus": "BLOCKED",
        "reviewDecision": (("CHANGES_REQUESTED" if any(r[2] == "CHANGES_REQUESTED" for r in reviews) else None)
                           if decision == "auto" else decision),
        "body": body,
        "files": {"totalCount": 2, "nodes": [{"path": "src/a.py", "additions": 10, "deletions": 2},
                                              {"path": "src/b.py", "additions": 1, "deletions": 0}]},
        "latestReviews": {"nodes": [{"state": r[2], "author": {"login": r[1]}} for r in reviews]},
        "latestOpinionatedReviews": {"nodes": [{"id": r[0], "state": r[2], "author": {"login": r[1]},
                                                "body": r[3] if len(r) > 3 else "",
                                                "submittedAt": "2026-09-21T09:00:00Z"} for r in reviews]},
        "reviewThreads": {"totalCount": len(threads), "nodes": list(threads)},
        "comments": {"totalCount": len(comments), "nodes": list(comments)},
        "commits": {"nodes": [{"commit": {"statusCheckRollup": {
            "state": "FAILURE", "contexts": {"totalCount": len(checks), "nodes": list(checks)}}}}]},
    }

expr = eval(sys.argv[2])
doc = {"data": {"viewer": {"login": "me"}, "repository": {"pullRequest": expr}}}
with open(sys.argv[1], "w") as fh:
    json.dump(doc, fh)
PY
}

# The stub answers `repo view` like gh would and serves the fixture for graphql.
STUB="$WORK/gh-stub"
cat > "$STUB" <<'EOS'
#!/bin/bash
case "$1" in
  repo) echo "acme/repo" ;;
  api)  cat "$STUB_JSON"; exit "${STUB_RC:-0}" ;;
  *)    echo "unexpected gh call: $*" >&2; exit 9 ;;
esac
EOS
chmod +x "$STUB"

ctx() {  # FIXTURE-NAME [pr-context args...]   (stdout+stderr, run outside any git repo)
  local name="$1"; shift
  ( cd "$WORK" && GH="$STUB" STUB_JSON="$WORK/$name.json" "$CTX" "$@" 2>&1 )
}

ok()   { PASS=$((PASS + 1)); echo "ok    $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL  $1"; echo "      got: $2"; }
expect() {  # CASE OUTPUT PATTERN  (extended regex that must match)
  if printf '%s\n' "$2" | grep -Eq -- "$3"; then ok "$1"; else bad "$1 (wanted /$3/)" "$2"; fi
}
reject() {  # CASE OUTPUT PATTERN  (extended regex that must NOT match)
  if printf '%s\n' "$2" | grep -Eq -- "$3"; then bad "$1 (did not want /$3/)" "$2"; else ok "$1"; fi
}
section() {  # OUTPUT HEADING -> the lines of that section, up to the next blank line
  printf '%s\n' "$1" | awk -v h="$2" 'index($0, h)==1{on=1; next} on&&/^$/{exit} on'
}

# ---- threads -----------------------------------------------------------------
fixture human 'pr(threads=[thread("T1", 1001, [comment(1001, body="rename this var"), comment(1002, body="and the test")], path="src/a.py", line=12)])'
out=$(ctx human 7 -R acme/repo); rc=$?
expect "unresolved human thread is actionable" "$(section "$out" "ACTIONABLE THREADS")" "src/a.py:12"
expect "  reply-to id is the first comment's databaseId" "$out" "reply-to id 1001"
expect "  every comment of the thread is shown" "$out" "rev: rename this var"
expect "  including the later one" "$out" "rev: and the test"
expect "  heading counts it" "$out" "ACTIONABLE THREADS \(1\)"
if [ "$rc" = 0 ]; then ok "  actionable feedback still exits 0"; else bad "  exit code" "rc=$rc"; fi

fixture mine 'pr(threads=[thread("T1", 1, [comment(1, body="MARK-ask"), comment(2, login="me", body="done")])])'
out=$(ctx mine 7 -R acme/repo)
expect "thread whose last comment is mine is not actionable" "$out" "ACTIONABLE THREADS \(0\)"
reject "  and none of it is listed" "$out" "MARK-ask"
expect "  it is counted as skipped" "$out" "threads: 1 last comment is mine"

fixture outdated 'pr(threads=[thread("T1", 1, [comment(1, body="MARK-old")], outdated=True)])'
out=$(ctx outdated 7 -R acme/repo)
expect "outdated thread is not actionable" "$out" "ACTIONABLE THREADS \(0\)"
reject "  and is not listed" "$out" "MARK-old"
expect "  it is counted as skipped" "$out" "threads: 1 outdated"

fixture resolved 'pr(threads=[thread("T1", 1, [comment(1, body="MARK-res")], resolved=True)])'
out=$(ctx resolved 7 -R acme/repo)
expect "resolved thread is not actionable" "$out" "ACTIONABLE THREADS \(0\)"
expect "  it is counted as skipped" "$out" "threads: 1 resolved"

fixture botthread 'pr(threads=[thread("T1", 1, [comment(1, login="ci-bot", typename="Bot", body="MARK-bot")])])'
out=$(ctx botthread 7 -R acme/repo)
expect "bot-started thread is not actionable" "$out" "ACTIONABLE THREADS \(0\)"
reject "  and is not listed" "$out" "MARK-bot"
expect "  it is counted as skipped" "$out" "threads: 1 bot-started"

# ---- conversation comments -----------------------------------------------------
fixture rocket 'pr(comments=[conv(10, body="MARK-handled", reactions=[("ROCKET","me")]), conv(11, body="MARK-open")])'
out=$(ctx rocket 7 -R acme/repo)
expect "unhandled human conversation comment is actionable" "$(section "$out" "ACTIONABLE CONVERSATION COMMENTS")" "id 11  rev: MARK-open"
reject "conversation comment with my ROCKET is not actionable" "$out" "MARK-handled"
expect "  and is counted as skipped" "$out" "comments: 1 handled \(rocket\)"

fixture thumbs 'pr(comments=[conv(10, body="MARK-thumb", reactions=[("THUMBS_UP","me")]), conv(12, login="ci-bot", typename="Bot", body="MARK-chatter")])'
out=$(ctx thumbs 7 -R acme/repo)
expect "my THUMBS_UP does not handle a comment" "$out" "id 10  rev: MARK-thumb"
reject "bot conversation comment is not actionable" "$out" "MARK-chatter"

# ---- already replied -------------------------------------------------------------
# Reviewer comment 50 (created 10:00, edited 12:00). My replies differ in time and anchor.
AR='conv(50, body="MARK-ask", edited="2026-09-21T12:00:00Z")'
fixture replied_ok "pr(comments=[$AR, conv(60, login=\"me\", created=\"2026-09-21T12:30:00Z\", body=\"fixed, see #issuecomment-50\")])"
out=$(ctx replied_ok 7 -R acme/repo)
expect "anchored reply newer than the last edit is already replied" "$out" "id 50  rev: \[already replied\] MARK-ask"
printf '%s' "$(ctx replied_ok 7 -R acme/repo --json)" | python3 -c '
import json, sys
c = json.load(sys.stdin)["actionable"]["comments"][0]
assert c["alreadyReplied"] is True and c["alreadyRepliedBy"]["databaseId"] == 60 and c["alreadyRepliedBy"]["url"], c
' && ok "  json carries alreadyReplied and alreadyRepliedBy" || bad "  json alreadyReplied" "$(ctx replied_ok 7 -R acme/repo --json)"

fixture replied_old "pr(comments=[$AR, conv(60, login=\"me\", created=\"2026-09-21T11:00:00Z\", body=\"fixed, see #issuecomment-50\")])"
out=$(ctx replied_old 7 -R acme/repo)
expect "reply that predates the latest edit is not already replied" "$out" "id 50  rev: MARK-ask"
reject "  and is not tagged" "$out" "already replied"

fixture replied_noanchor "pr(comments=[$AR, conv(60, login=\"me\", created=\"2026-09-21T12:30:00Z\", body=\"fixed\")])"
out=$(ctx replied_noanchor 7 -R acme/repo)
reject "reply without the #issuecomment anchor is not already replied" "$out" "already replied"

fixture replied_wrong "pr(comments=[$AR, conv(60, login=\"me\", created=\"2026-09-21T12:30:00Z\", body=\"see #issuecomment-5\")])"
out=$(ctx replied_wrong 7 -R acme/repo)
reject "anchor for a different comment id does not count (50 vs 5)" "$out" "already replied"

fixture replied_other "pr(comments=[$AR, conv(60, login=\"rev\", created=\"2026-09-21T12:30:00Z\", body=\"see #issuecomment-50\")])"
out=$(ctx replied_other 7 -R acme/repo --json)
if printf '%s' "$out" | python3 -c '
import json, sys
cs = {c["databaseId"]: c for c in json.load(sys.stdin)["actionable"]["comments"]}
assert cs[50]["alreadyReplied"] is False and "alreadyRepliedBy" not in cs[50], cs[50]
'; then ok "an anchored comment by someone else is not my reply"; else bad "someone else's anchor" "$out"; fi

fixture replied_prefix "pr(comments=[conv(12, body=\"MARK-twelve\"), conv(60, login=\"me\", created=\"2026-09-21T12:30:00Z\", body=\"see #issuecomment-123 only\")])"
out=$(ctx replied_prefix 7 -R acme/repo)
reject "an anchor for 123 does not mark comment 12 as replied" "$out" "already replied"
fixture replied_end "pr(comments=[conv(12, body=\"MARK-twelve\"), conv(60, login=\"me\", created=\"2026-09-21T12:30:00Z\", body=\"see #issuecomment-12\")])"
out=$(ctx replied_end 7 -R acme/repo)
expect "  but an anchor for 12 at end of body does" "$out" "id 12  rev: \[already replied\]"
fixture replied_punct "pr(comments=[conv(12, body=\"MARK-twelve\"), conv(60, login=\"me\", created=\"2026-09-21T12:30:00Z\", body=\"fixed (#issuecomment-12).\")])"
out=$(ctx replied_punct 7 -R acme/repo)
expect "  and so does one followed by punctuation" "$out" "id 12  rev: \[already replied\]"

# ---- change-request review bodies ----------------------------------------------
fixture crbody 'pr(reviews=[("R1","rev","CHANGES_REQUESTED","MARK-crbody " + "z" * 600),("R2","other","APPROVED","MARK-approval")])'
out=$(ctx crbody 7 -R acme/repo)
expect "standing change-request body is shown" "$out" "CHANGES REQUESTED REVIEW by rev"
expect "  with its text" "$out" "MARK-crbody"
reject "  but approvals' bodies are not" "$out" "MARK-approval"
ycount=$(printf '%s\n' "$out" | grep MARK-crbody | tr -cd z | wc -c | tr -d ' ')
if [ "$ycount" = 488 ]; then ok "  cut to 500 chars"; else bad "review body cut to 500 chars" "$ycount z's"; fi
out=$(ctx crbody 7 -R acme/repo --json)
if printf '%s' "$out" | python3 -c '
import json, sys
r = json.load(sys.stdin)["changesRequestedReviews"]
assert len(r) == 1 and r[0]["author"] == "rev" and r[0]["state"] == "CHANGES_REQUESTED", r
assert r[0]["submittedAt"] and len(r[0]["body"]) == 612, r
'; then ok "  json has author, state, submittedAt and the full body"; else bad "json changesRequestedReviews" "$out"; fi

fixture crstale2 'pr(reviews=[("R1","rev","CHANGES_REQUESTED","MARK-stale")], decision="APPROVED")'
out=$(ctx crstale2 7 -R acme/repo)
reject "stale change-request body (reviewDecision moved on) is not shown" "$out" "MARK-stale|CHANGES REQUESTED REVIEW"

# ---- checks --------------------------------------------------------------------
fixture checks 'pr(checks=[run_check("build"), run_check("lint", conclusion="FAILURE"), status_ctx("ci/legacy", "ERROR"), run_check("deploy", status="IN_PROGRESS", conclusion=None), status_ctx("ci/ok", "SUCCESS")])'
out=$(ctx checks 7 -R acme/repo)
expect "CHECKS summarises pass/fail/pending" "$out" "CHECKS: 2 pass, 2 fail, 1 pending"
expect "  failing check names are listed" "$out" "failing: lint, ci/legacy"
reject "  passing and pending names are not in the failing list" "$out" "failing:.*(build|deploy|ci/ok)"

# ---- reviews -------------------------------------------------------------------
fixture cr 'pr(reviews=[("R1","rev","CHANGES_REQUESTED"),("R2","other","APPROVED")])'
out=$(ctx cr 7 -R acme/repo)
expect "standing change request is named" "$out" "changes requested by rev"
fixture crstale 'pr(reviews=[("R1","rev","CHANGES_REQUESTED")], decision="APPROVED")'
out=$(ctx crstale 7 -R acme/repo)
reject "a change request that reviewDecision no longer reports is not standing" "$out" "changes requested by"

# ---- --json --------------------------------------------------------------------
fixture jsonall 'pr(threads=[thread("T1", 1001, [comment(1001, body="x" * 400)])], comments=[conv(11)], checks=[run_check("lint", conclusion="FAILURE")], body="b" * 2500)'
out=$(ctx jsonall 7 -R acme/repo --json)
if printf '%s' "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
t = d["actionable"]["threads"]
assert d["repo"] == "acme/repo" and d["viewer"] == "me", d
assert len(t) == 1 and t[0]["replyToId"] == 1001 and len(t[0]["comments"][0]["body"]) == 400, t
assert [c["databaseId"] for c in d["actionable"]["comments"]] == [11]
assert d["checks"]["failing"] == ["lint"], d["checks"]
assert len(d["pr"]["body"]) == 2500, "json body must not be truncated"
assert d["local"] == {"inRepo": False, "headMatchesPr": None}, d["local"]
'; then ok "--json emits one parseable object with the full detail"; else bad "--json parse/shape" "$out"; fi
text=$(ctx jsonall 7 -R acme/repo)
expect "text mode truncates the body" "$text" "body truncated, 2500 chars"
bcount=$(printf '%s\n' "$text" | grep '^bbbb' | tr -cd b | wc -c | tr -d ' ')
if [ "$bcount" = 2000 ]; then ok "  to exactly 2000 chars"; else bad "body cut to 2000 chars" "$bcount b's"; fi
xline=$(printf '%s\n' "$text" | grep '^    rev: xxx')
xcount=$(printf '%s' "$xline" | tr -cd x | wc -c | tr -d ' ')
if [ "$xcount" = 300 ]; then ok "text mode cuts a 400-char comment to 300 chars"; else bad "comment cut to 300 chars" "$xcount x's"; fi
expect "  and marks the cut with an ellipsis" "$xline" "xxx\.\.\.$"

# ---- resolving the PR ----------------------------------------------------------
out=$(ctx human https://github.com/acme/repo/pull/7)
expect "a PR URL works with no -R" "$out" "PR acme/repo#7"
out=$(ctx human 7)
expect "no -R and no URL falls back to gh repo view" "$out" "PR acme/repo#7"
out=$(ctx human 7 -R acme/repo)
expect "header names state, branches and head" "$out" "feature-7 -> main  head aaaaaaaaaaaa"

printf '%s' '{"data":{"viewer":{"login":"me"},"repository":{"pullRequest":null}},"errors":[{"type":"NOT_FOUND","message":"Could not resolve to a PullRequest with the number of 99."}]}' > "$WORK/missing.json"
out=$(STUB_RC=1 ctx missing 99 -R acme/repo); rc=$?
expect "missing PR says so" "$out" "not found"
if [ "$rc" = 1 ]; then ok "  and exits 1"; else bad "  and exits 1" "rc=$rc"; fi

# ---- local clone state ---------------------------------------------------------
REPO="$WORK/clone"
git init -q "$REPO" && git -C "$REPO" remote add origin https://github.com/acme/repo.git
git -C "$REPO" -c user.name=t -c user.email=t@example.test -c commit.gpgsign=false \
  commit -q --allow-empty -m "synthetic"
HEAD_SHA=$(git -C "$REPO" rev-parse HEAD)
inrepo() {  # FIXTURE-NAME [args...]
  local name="$1"; shift
  ( cd "$REPO" && GH="$STUB" STUB_JSON="$WORK/$name.json" "$CTX" "$@" 2>&1 )
}

out=$(inrepo human 7 -R acme/repo)
expect "head mismatch is reported inside the clone" "$out" "HEAD ${HEAD_SHA:0:12} != PR head"
expect "  with a warning" "$out" "WARNING: local HEAD is not the PR head"

fixture matching "pr(head=\"$HEAD_SHA\")"
out=$(inrepo matching 7 -R acme/repo)
expect "matching head is reported" "$out" "HEAD ${HEAD_SHA:0:12} == PR head"
reject "  without a warning" "$out" "WARNING"
expect "  and an untouched tree counts 0 uncommitted" "$out" "0 uncommitted"
expect "  and says there is no upstream" "$out" "no upstream"

: > "$REPO/dirty.txt"
out=$(inrepo matching 7 -R acme/repo)
expect "uncommitted files are counted" "$out" "1 uncommitted"

# Remotes whose host is an SSH alias or a non-default port still name acme/repo.
for url in git@github-work:acme/repo.git ssh://git@ssh.github.com:443/Acme/Repo.git https://example.test/acme/repo/; do
  git -C "$REPO" remote set-url origin "$url"
  out=$(inrepo matching 7 -R acme/repo)
  expect "remote $url is recognised" "$out" "HEAD ${HEAD_SHA:0:12} == PR head"
done
git -C "$REPO" remote set-url origin git@github-work:acme/repo-other.git
out=$(inrepo matching 7 -R acme/repo)
expect "a remote for a different repo with a shared prefix is not this repo" "$out" "^local: not this repo$"
git -C "$REPO" remote set-url origin https://github.com/acme/repo.git
out=$(inrepo matching 7 -R acme/repo --json)
printf '%s' "$out" | python3 -c '
import json, sys
l = json.load(sys.stdin)["local"]
assert l["inRepo"] is True and l["headMatchesPr"] is True, l
' && ok "json local.headMatchesPr is true in the clone" || bad "json local in clone" "$out"
out=$(ctx matching 7 -R acme/repo --json)
printf '%s' "$out" | python3 -c '
import json, sys
l = json.load(sys.stdin)["local"]
assert l["inRepo"] is False and "headMatchesPr" in l and l["headMatchesPr"] is None, l
' && ok "json local.headMatchesPr is present and null outside a clone" || bad "json local outside" "$out"

out=$(ctx matching 7 -R acme/repo)
expect "outside the repo's clone it says so" "$out" "^local: not this repo$"
out=$(inrepo matching 7 -R other/repo)
expect "inside a clone of a different repo it says so" "$out" "^local: not this repo$"

echo
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" = 0 ]
