#!/bin/bash
#
# Classifier tests for pr-fix-queue. Each case builds a GraphQL response, feeds
# it through PR_FIX_QUEUE_FIXTURE (no GitHub call, no state access, no launch),
# and asserts on the plan row the classifier prints.
#
# Usage: bin/tests/pr-fix-queue-classify.sh        (exit 1 if any case fails)

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
QUEUE="$HERE/../pr-fix-queue"
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

# fixture NAME 'PYTHON-EXPR'  — the expression is a list of PR dicts built with
# pr(...) and comment(...) below. The viewer is always "me".
fixture() {
  python3 - "$WORK/$1.json" "$2" <<'PY'
import json, sys

def comment(id, login="rev", typename="User", created="2026-09-21T10:00:00Z",
            edited=None, minimized=False, reactions=()):
    # reactions: (content, login, createdAt) tuples
    groups = {}
    for content, who, _ in reactions:
        groups[content] = groups.get(content, False) or who == "me"
    return {
        "databaseId": id, "createdAt": created, "lastEditedAt": edited,
        "isMinimized": minimized, "author": {"login": login, "__typename": typename},
        "reactionGroups": [{"content": k, "viewerHasReacted": v} for k, v in groups.items()],
        "reactions": {"nodes": [{"content": c, "createdAt": t, "user": {"login": w}}
                                for c, w, t in reactions]},
    }

def thread(id, first="rev", last="rev", last_id="L1", typename="User"):
    return {"id": id, "isResolved": False, "isOutdated": False,
            "firstComment": {"nodes": [{"author": {"login": first, "__typename": typename}}]},
            "lastComment": {"nodes": [{"id": last_id, "author": {"login": last}}]}}

def pr(num, comments=(), threads=(), total=None, mergeable="MERGEABLE", draft=False):
    return {
        "number": num, "title": "t%d" % num, "isDraft": draft,
        "updatedAt": "2026-09-21T12:00:00Z", "headRefOid": "h%d" % num,
        "headRefName": "feature-%d" % num, "isCrossRepository": False,
        "mergeable": mergeable, "reviewDecision": "REVIEW_REQUIRED",
        "repository": {"nameWithOwner": "acme/repo", "name": "repo"},
        "baseRef": {"name": "master", "target": {"oid": "b0"}},
        "latestReviews": {"nodes": []},
        "reviewThreads": {"nodes": list(threads)},
        "comments": {"totalCount": len(comments) if total is None else total,
                     "nodes": list(comments)},
    }

prs = eval(sys.argv[2])
doc = {"data": {"viewer": {"login": "me", "pullRequests": {"nodes": prs}}}}
with open(sys.argv[1], "w") as fh:
    json.dump(doc, fh)
PY
}

run() {  # NAME [queue args...] -> plan rows on stdout
  local name="$1"; shift
  PR_FIX_QUEUE_FIXTURE="$WORK/$name.json" PR_FIX_STATE="$WORK/state-must-not-exist.json" \
    "$QUEUE" "$@" 2>&1
}

ok()   { PASS=$((PASS + 1)); echo "ok    $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL  $1"; echo "      got: $2"; }

expect() {  # CASE OUTPUT PATTERN  (extended regex that must match)
  if printf '%s\n' "$2" | grep -Eq -- "$3"; then ok "$1"; else bad "$1 (wanted /$3/)" "$2"; fi
}
reject() {  # CASE OUTPUT PATTERN  (extended regex that must NOT match)
  if printf '%s\n' "$2" | grep -Eq -- "$3"; then bad "$1 (did not want /$3/)" "$2"; else ok "$1"; fi
}

T=$'\t'

fixture unanswered '[pr(1, [comment(100)])]'
out=$(run unanswered)
expect "unanswered human comment is a candidate" "$out" "^CAND${T}acme/repo${T}repo${T}1${T}"
expect "  fingerprint carries id@created and mr:0" "$out" "ic:100@2026-09-21T10:00:00Z\|mr:0${T}"
expect "  label says 1 comment(s)" "$out" "1 comment\(s\) — t1"

fixture rocket '[pr(2, [comment(100, reactions=[("ROCKET","me","2026-09-21T11:00:00Z")])])]'
out=$(run rocket)
expect "my ROCKET handles the comment" "$out" "^CLEAR${T}acme/repo${T}repo${T}2${T}"
reject "  and it is not a candidate" "$out" "^CAND"

fixture thumbs '[pr(3, [comment(100, reactions=[("THUMBS_UP","me","2026-09-21T11:00:00Z")])])]'
out=$(run thumbs)
expect "my THUMBS_UP does not handle it" "$out" "^CAND${T}.*ic:100@"

fixture otherrocket '[pr(4, [comment(100, reactions=[("ROCKET","someone","2026-09-21T11:00:00Z")])])]'
out=$(run otherrocket)
expect "someone else's ROCKET does not handle it" "$out" "^CAND${T}.*ic:100@"

fixture edited '[pr(5, [comment(100, edited="2026-09-21T12:00:00Z", reactions=[("ROCKET","me","2026-09-21T11:00:00Z")])])]'
out=$(run edited)
expect "edit after my ROCKET re-opens it" "$out" "^CAND${T}"
expect "  and the fingerprint uses the edit time" "$out" "ic:100@2026-09-21T12:00:00Z"

fixture rerocket '[pr(6, [comment(100, edited="2026-09-21T12:00:00Z", reactions=[("ROCKET","me","2026-09-21T13:00:00Z")])])]'
out=$(run rerocket)
expect "ROCKET placed after the edit handles it" "$out" "^CLEAR${T}"

fixture myreply '[pr(7, [comment(100), comment(200, login="me", created="2026-09-21T11:00:00Z")])]'
out=$(run myreply)
expect "a later reply of mine does NOT handle it" "$out" "^CAND${T}.*ic:100@"
expect "  but it moves the fingerprint (mr:200)" "$out" "\|mr:200${T}"

fixture bot '[pr(8, [comment(100, login="amazon-q", typename="Bot")])]'
out=$(run bot)
expect "bot conversation comment is ignored" "$out" "^CLEAR${T}"
out=$(run bot --include-bots)
expect "  even with --include-bots" "$out" "^CLEAR${T}"

fixture minimized '[pr(9, [comment(100, minimized=True), comment(101, login="me")])]'
out=$(run minimized)
expect "minimized and my own comments are ignored" "$out" "^CLEAR${T}"

fixture both '[pr(10, [comment(100)], threads=[thread("T1")])]'
out=$(run both)
expect "threads + comments: both labels" "$out" "1 thread\(s\), 1 comment\(s\)"
expect "  and both fingerprint parts" "$out" "th:T1:L1\|ic:100@[^|]*\|mr:0"

fixture botthread '[pr(11, threads=[thread("T1", first="ci-bot", typename="Bot")])]'
out=$(run botthread)
expect "bot thread ignored by default" "$out" "^CLEAR${T}"
out=$(run botthread --include-bots)
expect "  but --include-bots still applies to threads" "$out" "^CAND${T}.*th:T1:L1"

fixture truncated '[pr(12, [comment(100)], total=73)]'
out=$(run truncated)
expect "more than 50 comments is called out" "$out" "only newest 50 comments checked"

fixture unknown '[pr(13, mergeable="UNKNOWN")]'
start=$(date +%s)
out=$(run unknown)
took=$(( $(date +%s) - start ))
expect "UNKNOWN mergeability is SKIP with its reason intact" "$out" "^SKIP${T}acme/repo${T}repo${T}13${T}.*mergeability still UNKNOWN"
reject "  and is not CLEAR (state must survive)" "$out" "^CLEAR"
if [ "$took" -lt 2 ]; then ok "  fixture mode does not sleep through the re-poll (${took}s)"; else bad "  fixture mode slept" "${took}s"; fi

fixture draft '[pr(14, [comment(100)], draft=True)]'
out=$(run draft)
reject "draft PR produces no row at all (no CLEAR, state untouched)" "$out" "${T}14${T}"

if [ -e "$WORK/state-must-not-exist.json" ] || [ -e "$WORK/state-must-not-exist.json.lock" ]; then
  bad "fixture mode touched the state file" "$(ls "$WORK")"
else
  ok "fixture mode never touches the state file"
fi

echo
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" = 0 ]
