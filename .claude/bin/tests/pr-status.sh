#!/bin/bash
#
# Tests for pr-status. `gh` is replaced through the GH env var by a stub that serves synthetic
# GraphQL answers from a per-case world.json and logs every call (no network).
# Everything here is made up: orgs acme and globex, repos widgets/gadgets/gizmos, PR numbers 1-9.
# "fullbay" appears only as the default-org string the script is expected to use.
#
# Usage: bin/tests/pr-status.sh        (exit 1 if any case fails)

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
STATUS="$HERE/../pr-status"
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
export GH_PRS_RETRY_DELAY=0

# Stub gh. $STUB_DIR/world.json: {"owner/repo": {"prs": {"N": {state, isDraft, reviewDecision,
# mergeable, headRefOid, baseRefName, updatedAt, rollup}}, "fail": true (always HTTP 500-style
# failure), "flaky": K (the first K calls answer HTTP 502, then it works)}}. A repo that is absent
# answers "Could not resolve to a Repository" with gh's non-zero exit; a PR number that is absent
# answers null plus an error. Calls go to $STUB_DIR/calls.log as "owner/repo N N...". Any call
# that is not `api graphql`, or whose query mentions "mutation", exits 99 (read-only check).
STUB="$WORK/gh"
cat > "$STUB" <<'EOS'
#!/usr/bin/env python3
import json, os, re, sys
d = os.environ["STUB_DIR"]
a = sys.argv[1:]
if a[:2] != ["api", "graphql"]:
    print("unexpected gh call: " + " ".join(a), file=sys.stderr); sys.exit(99)
f = {}
for i, x in enumerate(a):
    if x == "-f" and "=" in a[i + 1]:
        k, v = a[i + 1].split("=", 1); f[k] = v
q = f["query"]
if "mutation" in q.lower():
    print("mutation sent: " + q, file=sys.stderr); sys.exit(99)
repo = f["owner"] + "/" + f["name"]
world = json.load(open(d + "/world.json"))
nums = [int(n) for n in re.findall(r"p(\d+):pullRequest", q)]
open(d + "/calls.log", "a").write(repo + " " + " ".join(str(n) for n in nums) + "\n")
w = world.get(repo)
if w is not None and w.get("fail"):
    print("gh: Server Error (HTTP 500)", file=sys.stderr); sys.exit(1)
if w is not None and w.get("flaky"):
    cf = d + "/flaky-" + repo.replace("/", "_")
    n = int(open(cf).read()) if os.path.exists(cf) else 0
    if n < w["flaky"]:
        open(cf, "w").write(str(n + 1))
        print("gh: HTTP 502: Bad Gateway", file=sys.stderr); sys.exit(1)
if w is None:
    print(json.dumps({"data": {"repository": None}, "errors": [{"type": "NOT_FOUND", "message": "Could not resolve to a Repository with the name '%s'." % repo}]}))
    sys.exit(1)
out, missing = {}, False
for n in nums:
    p = w.get("prs", {}).get(str(n))
    if p is None:
        out["p%d" % n] = None; missing = True; continue
    node = {k: p.get(k) for k in ("state", "isDraft", "reviewDecision", "mergeable", "headRefOid", "baseRefName", "updatedAt")}
    r = p.get("rollup")
    node["commits"] = {"nodes": [{"commit": {"statusCheckRollup": {"state": r} if r else None}}]}
    out["p%d" % n] = node
res = {"data": {"repository": out}}
if missing:
    res["errors"] = [{"type": "NOT_FOUND", "message": "Could not resolve to a PullRequest"}]
print(json.dumps(res)); sys.exit(1 if missing else 0)
EOS
chmod +x "$STUB"

ok()  { PASS=$((PASS + 1)); echo "ok    $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL  $1"; echo "      got: $2"; }
expect() { if printf '%s\n' "$2" | grep -Eq -- "$3"; then ok "$1"; else bad "$1 (wanted /$3/)" "$2"; fi; }
reject() { if printf '%s\n' "$2" | grep -Eq -- "$3"; then bad "$1 (did not want /$3/)" "$2"; else ok "$1"; fi; }
rc_is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (wanted exit $3)" "exit $2"; fi; }
eq()     { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (wanted '$3')" "'$2'"; fi; }

new_world() {  # NAME WORLD_JSON -> fresh STUB_DIR
  STUB_DIR="$WORK/$1"; mkdir -p "$STUB_DIR"; export STUB_DIR
  echo "$2" > "$STUB_DIR/world.json"
}
run() {  # args... -> OUT (stdout), ERR (stderr), RC
  OUT=$(cd "$WORK" && GH="$STUB" "$STATUS" "$@" 2>"$STUB_DIR/err.txt"); RC=$?
  ERR=$(cat "$STUB_DIR/err.txt")
}
calls() { cat "$STUB_DIR/calls.log" 2>/dev/null; }
ncalls() { calls | grep -c . ; }
jq_() {  # EXPR -> python expression over the parsed stdout (as d)
  printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))' "$1"
}
row() { printf '%s\n' "$OUT" | grep -F -- "$1"; }  # the table row that names a ref

# pr FIELDS: a PR object. Defaults make an approved, green, mergeable open PR on main.
pr() {  # STATE [key=value ...] -> JSON
  python3 - "$@" <<'EOS'
import json, sys
state, *kv = sys.argv[1:]
d = {"state": state, "isDraft": False, "reviewDecision": "APPROVED", "mergeable": "MERGEABLE",
     "headRefOid": "abcdef0123456789abcdef0123456789abcdef01", "baseRefName": "main",
     "updatedAt": "2026-03-04T05:06:07Z", "rollup": "SUCCESS"}
for x in kv:
    k, v = x.split("=", 1)
    d[k] = {"true": True, "false": False, "null": None}.get(v, v)
print(json.dumps(d))
EOS
}

# ---- ref syntaxes and the default org -------------------------------------------------------
new_world refs "{\"fullbay/widgets\":{\"prs\":{\"1\":$(pr OPEN)}},
  \"acme/widgets\":{\"prs\":{\"2\":$(pr OPEN),\"3\":$(pr OPEN),\"4\":$(pr OPEN)}},
  \"globex/gadgets\":{\"prs\":{\"5\":$(pr OPEN)}}}"
run widgets:1 widgets#1 acme/widgets:2 acme/widgets#3 globex/gadgets#5
rc_is "all five syntaxes resolve: exit 0" "$RC" 0
expect "repo:N uses the default org" "$OUT" '^fullbay/widgets#1 '
eq "repo:N and repo#N are the same PR (shown twice, input order)" "$(printf '%s\n' "$OUT" | grep -c '^fullbay/widgets#1 ')" 2
expect "owner/repo:N keeps its owner" "$OUT" '^acme/widgets#2 '
expect "owner/repo#N keeps its owner" "$OUT" '^acme/widgets#3 '
expect "another owner and repo" "$OUT" '^globex/gadgets#5 '
eq "the duplicated ref is asked for once" "$(calls | grep -c '^fullbay/widgets ')" 1
eq "the first call asked for PR 1 only" "$(calls | grep '^fullbay/widgets ')" "fullbay/widgets 1"

new_world org "{\"acme/widgets\":{\"prs\":{\"1\":$(pr OPEN)}},\"fullbay/widgets\":{}}"
run --org acme widgets:1
rc_is "--org changes the default owner: exit 0" "$RC" 0
expect "  the row is under acme" "$OUT" '^acme/widgets#1 '
run widgets:1 --org acme
expect "--org after the refs works too" "$OUT" '^acme/widgets#1 '
run --org acme globex/widgets:1
expect "an explicit owner beats --org" "$(calls | tail -1)" '^globex/widgets 1$'

# ---- batching ---------------------------------------------------------------------------------
new_world batch "{\"acme/widgets\":{\"prs\":{\"1\":$(pr OPEN),\"2\":$(pr MERGED),\"3\":$(pr CLOSED)}},
  \"acme/gadgets\":{\"prs\":{\"7\":$(pr OPEN),\"8\":$(pr OPEN)}}}"
run acme/widgets:1 acme/gadgets:7 acme/widgets:2 acme/gadgets:8 acme/widgets:3
rc_is "two repos, five PRs: exit 0" "$RC" 0
eq "one call per repo: 2 calls for 5 PRs" "$(ncalls)" 2
eq "  the widgets call carries all three of its PRs" "$(calls | grep '^acme/widgets ')" "acme/widgets 1 2 3"
eq "  the gadgets call carries both of its" "$(calls | grep '^acme/gadgets ')" "acme/gadgets 7 8"
eq "rows keep input order" "$(printf '%s\n' "$OUT" | sed -n '2,6p' | awk '{print $1}' | tr '\n' ' ')" \
   "acme/widgets#1 acme/gadgets#7 acme/widgets#2 acme/gadgets#8 acme/widgets#3 "
new_world batchcase "{\"Acme/Widgets\":{\"prs\":{\"1\":$(pr OPEN),\"2\":$(pr OPEN)}},\"acme/widgets\":{}}"
run Acme/Widgets:1 acme/widgets:2
eq "the same repo spelled in two cases is one call" "$(ncalls)" 1

# ---- states and columns -----------------------------------------------------------------------
new_world states "{\"acme/widgets\":{\"prs\":{
  \"1\":$(pr OPEN),
  \"2\":$(pr OPEN isDraft=true reviewDecision=REVIEW_REQUIRED rollup=PENDING mergeable=UNKNOWN),
  \"3\":$(pr MERGED reviewDecision=null baseRefName=release headRefOid=1111111222222233333334444444555555566666),
  \"4\":$(pr CLOSED reviewDecision=CHANGES_REQUESTED rollup=FAILURE mergeable=CONFLICTING),
  \"5\":$(pr OPEN rollup=null),
  \"6\":$(pr OPEN rollup=ERROR),
  \"7\":$(pr OPEN rollup=EXPECTED)}}}"
run acme/widgets:1 acme/widgets:2 acme/widgets:3 acme/widgets:4 acme/widgets:5 acme/widgets:6 acme/widgets:7
rc_is "every state readable: exit 0" "$RC" 0
expect "header row" "$(printf '%s\n' "$OUT" | head -1)" '^REF +STATE +REVIEW +CHECKS +MERGEABLE +HEAD +BASE +UPDATED$'
expect "OPEN row: every column" "$(row 'acme/widgets#1 ')" '^acme/widgets#1 +OPEN +APPROVED +SUCCESS +MERGEABLE +abcdef0 +main +2026-03-04$'
expect "an open draft shows as DRAFT" "$(row 'acme/widgets#2 ')" '^acme/widgets#2 +DRAFT +REVIEW_REQUIRED +PENDING +UNKNOWN '
expect "MERGED: no review decision is -, sha7 and base" "$(row 'acme/widgets#3 ')" '^acme/widgets#3 +MERGED +- +SUCCESS +MERGEABLE +1111111 +release +2026-03-04$'
expect "CLOSED with changes requested, failing, conflicting" "$(row 'acme/widgets#4 ')" '^acme/widgets#4 +CLOSED +CHANGES_REQUESTED +FAILURE +CONFLICTING '
expect "no checks rollup is -" "$(row 'acme/widgets#5 ')" '^acme/widgets#5 +OPEN +APPROVED +- +MERGEABLE '
expect "an ERROR rollup reads FAILURE" "$(row 'acme/widgets#6 ')" '^acme/widgets#6 +OPEN +APPROVED +FAILURE '
expect "an EXPECTED rollup reads PENDING" "$(row 'acme/widgets#7 ')" '^acme/widgets#7 +OPEN +APPROVED +PENDING '
eq "counts line (drafts count as open)" "$(printf '%s\n' "$OUT" | tail -1)" "5 open (4 approved, 1 draft), 1 merged, 1 closed, 0 unreadable"
eq "the columns line up: one start column for STATE on every row" \
   "$(printf '%s\n' "$OUT" | sed -n '1,8p' | awk '{print index($0, $2)}' | sort -u | wc -l | tr -d ' ')" 1

# ---- a missing PR in an otherwise good repo ----------------------------------------------------
new_world missing "{\"acme/widgets\":{\"prs\":{\"1\":$(pr OPEN),\"3\":$(pr MERGED)}}}"
run acme/widgets:1 acme/widgets:2 acme/widgets:3
rc_is "a missing PR: exit 1" "$RC" 1
eq "  still one call" "$(ncalls)" 1
expect "  the missing PR is UNREADABLE with its reason" "$(row 'acme/widgets#2 ')" '^acme/widgets#2 +UNREADABLE +PR acme/widgets#2 not found$'
expect "  its neighbours still print" "$OUT" '^acme/widgets#1 +OPEN '
expect "  and the merged one" "$OUT" '^acme/widgets#3 +MERGED '
eq "  counts" "$(printf '%s\n' "$OUT" | tail -1)" "1 open (1 approved), 1 merged, 0 closed, 1 unreadable"

# ---- a whole repo that gh fails on -------------------------------------------------------------
new_world repofail "{\"acme/widgets\":{\"prs\":{\"1\":$(pr OPEN)}},\"acme/gadgets\":{\"fail\":true,\"prs\":{}}}"
run acme/gadgets:4 acme/widgets:1 acme/gadgets:5
rc_is "a repo gh fails on: exit 1" "$RC" 1
expect "  first ref UNREADABLE with gh's first line" "$(row 'acme/gadgets#4 ')" '^acme/gadgets#4 +UNREADABLE +gh api graphql failed for acme/gadgets: gh: Server Error \(HTTP 500\)$'
expect "  second ref of that repo too" "$(row 'acme/gadgets#5 ')" '^acme/gadgets#5 +UNREADABLE +gh api graphql failed for acme/gadgets'
expect "  the other repo still prints" "$OUT" '^acme/widgets#1 +OPEN '
eq "  a persistent 5xx is retried once, then given up (two calls for gadgets)" "$(calls | grep -c '^acme/gadgets ')" 2
new_world norepo "{\"acme/widgets\":{\"prs\":{\"1\":$(pr OPEN)}}}"
run acme/nothere:1 acme/widgets:1
rc_is "a repo that does not exist or is not visible: exit 1" "$RC" 1
expect "  says so" "$(row 'acme/nothere#1 ')" '^acme/nothere#1 +UNREADABLE +gh api graphql failed for acme/nothere: Could not resolve to a Repository'
expect "  the good repo still prints" "$OUT" '^acme/widgets#1 +OPEN '
eq "  a not-found answer is not retried (one call for nothere)" "$(calls | grep -c '^acme/nothere ')" 1
run --json acme/nothere:1 acme/widgets:1
eq "  --json carries the error and the state" "$(jq_ "[(x['state'], 'Could not resolve' in x.get('error','')) for x in d][0]")" "('UNREADABLE', True)"
OUT=$(cd "$WORK" && GH="$WORK/no-such-gh" "$STATUS" acme/widgets:1 2>&1); RC=$?
rc_is "gh not installed: exit 1, not a crash" "$RC" 1
expect "  UNREADABLE and says gh is missing" "$OUT" 'UNREADABLE +.*not installed'

# ---- 502 then success --------------------------------------------------------------------------
new_world flaky "{\"acme/widgets\":{\"flaky\":1,\"prs\":{\"1\":$(pr OPEN),\"2\":$(pr MERGED)}}}"
run acme/widgets:1 acme/widgets:2
rc_is "one 502 then success: exit 0" "$RC" 0
eq "  retried once: two calls" "$(ncalls)" 2
expect "  both rows read" "$OUT" '^acme/widgets#2 +MERGED '
new_world flaky2 "{\"acme/widgets\":{\"flaky\":2,\"prs\":{\"1\":$(pr OPEN)}}}"
run acme/widgets:1
rc_is "two 502s in a row: exit 1" "$RC" 1
eq "  only one retry: two calls, not three" "$(ncalls)" 2
expect "  UNREADABLE with the 502 line" "$OUT" 'UNREADABLE +gh api graphql failed for acme/widgets: gh: HTTP 502'

# ---- --json ------------------------------------------------------------------------------------
new_world json "{\"acme/widgets\":{\"prs\":{\"1\":$(pr OPEN isDraft=true reviewDecision=null rollup=null),\"2\":$(pr MERGED)}}}"
run --json acme/widgets:1 acme/widgets:2 acme/widgets:9
rc_is "--json with an unreadable ref: exit 1" "$RC" 1
eq "a JSON array, one object per ref" "$(jq_ 'len(d)')" 3
eq "  in input order" "$(jq_ "[x['ref'] for x in d]")" "['acme/widgets#1', 'acme/widgets#2', 'acme/widgets#9']"
eq "  fields" "$(jq_ "sorted(d[1])")" "['baseRef', 'checks', 'headSha', 'mergeable', 'number', 'owner', 'ref', 'repo', 'reviewDecision', 'state', 'updatedAt']"
eq "  values (draft, no decision, no checks are null)" "$(jq_ "(d[0]['state'], d[0]['reviewDecision'], d[0]['checks'], d[0]['number'])")" "('DRAFT', None, None, 1)"
eq "  full sha and timestamp" "$(jq_ "(d[1]['headSha'], d[1]['updatedAt'])")" "('abcdef0123456789abcdef0123456789abcdef01', '2026-03-04T05:06:07Z')"
eq "  unreadable object" "$(jq_ "(d[2]['state'], d[2]['error'])")" "('UNREADABLE', 'PR acme/widgets#9 not found')"
reject "  no counts line in JSON mode" "$OUT" 'unreadable$'
run --json acme/widgets:2
rc_is "--json all readable: exit 0" "$RC" 0

# ---- usage --------------------------------------------------------------------------------------
new_world usage '{}'
run
rc_is "no refs: exit 2" "$RC" 2
expect "  usage on stderr" "$ERR" 'usage: pr-status'
for bad_ref in widgets widgets:0 widgets:x widgets# :3 a/b/c:1 widgets:1x 'wid gets:1' -- ; do
  run $bad_ref
  rc_is "bad ref '$bad_ref': exit 2" "$RC" 2
done
run acme/widgets:1 bogus
rc_is "one good ref and one bad: exit 2" "$RC" 2
expect "  names the bad ref" "$ERR" 'bogus'
eq "  and makes no gh call" "$(ncalls)" 0
run --frobnicate widgets:1
rc_is "an unknown option: exit 2" "$RC" 2
run --org
rc_is "--org without a value: exit 2" "$RC" 2
run -h
rc_is "-h: exit 0" "$RC" 0
expect "  prints usage and the ref syntax" "$OUT" 'usage: pr-status'
expect "  mentions the default org" "$OUT" 'default fullbay'

# ---- read-only ------------------------------------------------------------------------------------
new_world ro "{\"acme/widgets\":{\"prs\":{\"1\":$(pr OPEN)}}}"
run acme/widgets:1
eq "only queries are sent (the stub exits 99 on a mutation or a non-graphql call)" "$RC" 0
reject "  no stub complaint" "$ERR" 'unexpected gh call|mutation sent'

echo
echo "pr-status: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
