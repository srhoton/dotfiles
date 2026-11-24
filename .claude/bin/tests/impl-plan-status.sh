#!/bin/bash
#
# Tests for impl-plan-status. `gh` is replaced through the GH env var by a stub that serves
# synthetic GraphQL answers from a per-case world.json and logs every call (no network).
# Everything here is made up: repos widgets/gadgets/gizmos, tickets ZZ-<n>, org fullbay/acme.
#
# Usage: bin/tests/impl-plan-status.sh        (exit 1 if any case fails)

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
STATUS="$HERE/../impl-plan-status"
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

# Stub gh. $STUB_DIR/world.json: {"owner/repo": {"prs": {"N": "OPEN|MERGED|CLOSED"},
# "prs-list": [{number,title,headRefName,state}...] (one page), "pages": [[...],[...]],
# "fail": true}}. A repo that is absent answers "Could not resolve to a Repository"; a PR
# number that is absent answers null plus an error, with gh's non-zero exit. Calls go to
# $STUB_DIR/calls.log as "status owner/repo N..." or "discover owner/repo after=<cursor>".
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
repo = f["owner"] + "/" + f["name"]
world = json.load(open(d + "/world.json"))
log = open(d + "/calls.log", "a")
if world.get(repo, {}).get("fail"):
    log.write("fail " + repo + "\n"); print("gh: HTTP 502 boom", file=sys.stderr); sys.exit(1)
if repo not in world:
    log.write("missing " + repo + "\n")
    print(json.dumps({"data": {"repository": None}, "errors": [{"type": "NOT_FOUND", "message": "Could not resolve to a Repository"}]}))
    sys.exit(1)
w = world[repo]
q = f["query"]
if "pullRequests(" in q:
    after = f.get("after", "")
    log.write("discover " + repo + " after=" + after + "\n")
    pages = w.get("pages") or [w.get("prs-list", [])]
    idx = int(after) if after else 0
    out = {"data": {"repository": {"pullRequests": {
        "pageInfo": {"hasNextPage": idx + 1 < len(pages), "endCursor": str(idx + 1)}, "nodes": pages[idx]}}}}
    print(json.dumps(out)); sys.exit(0)
nums = [int(n) for n in re.findall(r"p(\d+):pullRequest", q)]
log.write("status " + repo + " " + " ".join(str(n) for n in nums) + "\n")
repo_out, missing = {}, False
for n in nums:
    st = w.get("prs", {}).get(str(n))
    repo_out["p%d" % n] = {"state": st} if st else None
    missing = missing or not st
res = {"data": {"repository": repo_out}}
if missing:
    res["errors"] = [{"type": "NOT_FOUND", "message": "Could not resolve to a PullRequest"}]
print(json.dumps(res)); sys.exit(1 if missing else 0)
EOS
chmod +x "$STUB"

# mk.py: write a plan.json from partial steps. A step needs only an id; the rest is filled in.
cat > "$WORK/mk.py" <<'EOS'
import json, sys
path, steps, questions = sys.argv[1], json.loads(sys.argv[2]), json.loads(sys.argv[3])
full = []
for s in steps:
    d = {"phase": "p1", "title": "Step " + s["id"], "work": "Do the work.", "plain": "Plain words.",
         "repos": [{"name": "widgets", "exists": True}]}
    d.update(s)
    full.append(d)
doc = {"plan": {"title": "Fixture Plan", "slug": "fixture", "source": {"kind": "session", "ref": ""},
                "summary": "A made-up plan."},
       "phases": [{"id": "p1", "title": "Phase one"}], "steps": full, "questions": questions}
json.dump(doc, open(path, "w"), indent=2)
EOS

ok()  { PASS=$((PASS + 1)); echo "ok    $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL  $1"; echo "      got: $2"; }
expect() { if printf '%s\n' "$2" | grep -Eq -- "$3"; then ok "$1"; else bad "$1 (wanted /$3/)" "$2"; fi; }
reject() { if printf '%s\n' "$2" | grep -Eq -- "$3"; then bad "$1 (did not want /$3/)" "$2"; else ok "$1"; fi; }
rc_is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (wanted exit $3)" "exit $2"; fi; }
eq()     { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (wanted '$3')" "'$2'"; fi; }

new_world() {  # NAME [WORLD_JSON] -> fresh STUB_DIR and plan path
  STUB_DIR="$WORK/$1"; mkdir -p "$STUB_DIR"; export STUB_DIR
  P="$STUB_DIR/plan.json"
  if [ -n "${2:-}" ]; then echo "$2" > "$STUB_DIR/world.json"; else echo '{}' > "$STUB_DIR/world.json"; fi
}
plan() {  # STEPS_JSON [QUESTIONS_JSON]
  python3 "$WORK/mk.py" "$P" "$1" "${2:-[]}"
}
run() {  # args... -> OUT (stdout), ERR (stderr), RC
  OUT=$(cd "$WORK" && GH="$STUB" "$STATUS" "$@" 2>"$STUB_DIR/err.txt"); RC=$?
  ERR=$(cat "$STUB_DIR/err.txt")
}
pj() {  # EXPR -> value of a python expression over the parsed plan.json (as d)
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$P" "$1"
}
calls() { cat "$STUB_DIR/calls.log" 2>/dev/null; }
status_of() { pj "[s for s in d['steps'] if s['id']=='$1'][0].get('status')"; }

W='"fullbay/widgets"'

# ---- status rules ----------------------------------------------------------------------
new_world rules "{$W:{\"prs\":{\"1\":\"MERGED\",\"2\":\"MERGED\",\"3\":\"OPEN\",\"4\":\"CLOSED\",\"5\":\"OPEN\"}}}"
plan '[{"id":"red1"},
       {"id":"yel1","prs":["fullbay/widgets#3"]},
       {"id":"yel2","prs":["fullbay/widgets#1","fullbay/widgets#3"]},
       {"id":"grn1","prs":["fullbay/widgets#1"]},
       {"id":"grn2","prs":["fullbay/widgets#1","fullbay/widgets#2"]},
       {"id":"org1","designGate":{"required":true,"reason":"new mechanism","approved":null}},
       {"id":"org2","prs":["fullbay/widgets#1"],"designGate":{"required":true,"reason":"new mechanism","approved":null}},
       {"id":"org3","prs":["fullbay/widgets#3"],"designGate":{"required":true,"reason":"new mechanism"}},
       {"id":"app1","prs":["fullbay/widgets#1"],"designGate":{"required":true,"reason":"new mechanism","approved":"2026-11-01"}},
       {"id":"nog1","prs":["fullbay/widgets#3"],"designGate":{"required":false}},
       {"id":"man1","doneWhen":"manual","done":true},
       {"id":"man2","doneWhen":"manual"},
       {"id":"man3","doneWhen":"manual","prs":["fullbay/widgets#1"]},
       {"id":"man4","doneWhen":"manual","done":true,"prs":["fullbay/widgets#3"]},
       {"id":"man5","doneWhen":"manual","prs":["fullbay/widgets#3"]},
       {"id":"mer1","done":true},
       {"id":"clo1","prs":["fullbay/widgets#4"]},
       {"id":"clo2","prs":["fullbay/widgets#1","fullbay/widgets#4"]},
       {"id":"clo3","prs":["fullbay/widgets#4","fullbay/widgets#5"]}]'
run "$P" --write
rc_is "scoring a valid plan: exit 0" "$RC" 0
eq "no PRs: red" "$(status_of red1)" red
eq "an open PR: yellow" "$(status_of yel1)" yellow
eq "some PRs merged, others open: yellow" "$(status_of yel2)" yellow
eq "the only PR merged: green" "$(status_of grn1)" green
eq "every PR merged: green" "$(status_of grn2)" green
eq "design gate, no PRs: orange" "$(status_of org1)" orange
eq "design gate over every PR merged: orange, not green" "$(status_of org2)" orange
eq "design gate over an open PR: orange, not yellow" "$(status_of org3)" orange
eq "an approved gate falls through to the PR rules: green" "$(status_of app1)" green
eq "a gate that is not required is ignored: yellow" "$(status_of nog1)" yellow
eq "manual and done, no PR: green" "$(status_of man1)" green
eq "manual, not done, no PR: red" "$(status_of man2)" red
eq "manual with merged PRs but not done: yellow" "$(status_of man3)" yellow
eq "manual and done beats an open PR: green (green is ranked above yellow)" "$(status_of man4)" green
eq "manual with an open PR, not done: yellow" "$(status_of man5)" yellow
eq "doneWhen merged ignores done:true without PRs: red" "$(status_of mer1)" red
eq "only a closed-unmerged PR: red (ignored)" "$(status_of clo1)" red
eq "merged plus closed-unmerged: green (closed ignored)" "$(status_of clo2)" green
eq "open plus closed-unmerged: yellow" "$(status_of clo3)" yellow
expect "statusWhy for green names the PRs" "$(pj "[s for s in d['steps'] if s['id']=='grn2'][0]['statusWhy']")" 'all PRs merged: fullbay/widgets#1, fullbay/widgets#2'
expect "statusWhy for orange carries the reason" "$(pj "[s for s in d['steps'] if s['id']=='org1'][0]['statusWhy']")" 'design gate not approved: new mechanism'
expect "closed-unmerged warns" "$OUT" 'clo1: fullbay/widgets#4 was closed without merging; ignored'
expect "a PR before design approval warns (merged)" "$OUT" 'org2: PR before design approval \(fullbay/widgets#1\)'
expect "a PR before design approval warns (open)" "$OUT" 'org3: PR before design approval'
reject "no PR-before-approval warning without a PR" "$OUT" 'org1: PR before'
reject "no PR-before-approval warning once approved" "$OUT" 'app1: PR before'
eq "one gh call per repo, however many PRs" "$(calls | grep -c '^status ')" 1
expect "  and it carries every distinct PR number" "$(calls)" '^status fullbay/widgets 1 2 3 4 5$'
eq "prStates are written for the step's own PRs" "$(pj "sorted([s for s in d['steps'] if s['id']=='clo3'][0]['prStates'].items())")" "[('fullbay/widgets#4', 'CLOSED'), ('fullbay/widgets#5', 'OPEN')]"

# ---- change table, --write, idempotence --------------------------------------------------
new_world table "{$W:{\"prs\":{\"1\":\"OPEN\"}}}"
plan '[{"id":"A","prs":["fullbay/widgets#1"]},{"id":"B"}]'
cp "$P" "$STUB_DIR/orig.json"
run "$P"
expect "first run: the table shows (none) -> yellow" "$OUT" '^A +\(none\) -> yellow +PR open: fullbay/widgets#1'
expect "  and (none) -> red" "$OUT" '^B +\(none\) -> red +no PRs'
expect "  and the counts line" "$OUT" '^status: 0 green · 1 yellow · 0 orange · 1 red$'
if cmp -s "$P" "$STUB_DIR/orig.json"; then ok "without --write the plan file is untouched"; else bad "plan file changed without --write" "$(cat "$P")"; fi
run "$P" --write
eq "--write stores status" "$(status_of A)" yellow
eq "  and statusWhy" "$(pj "d['steps'][0]['statusWhy']")" "PR open: fullbay/widgets#1"
eq "  and the PR states" "$(pj "d['steps'][0]['prStates']")" "{'fullbay/widgets#1': 'OPEN'}"
eq "  and the warnings list" "$(pj "d['warnings']")" "[]"
eq "  and leaves the authored fields alone" "$(pj "(d['steps'][0]['prs'], d['plan']['title'])")" "(['fullbay/widgets#1'], 'Fixture Plan')"
run "$P" --write
expect "second run with nothing new: no changes" "$OUT" '^no changes$'
echo "{$W:{\"prs\":{\"1\":\"MERGED\"}}}" > "$STUB_DIR/world.json"
run "$P" --write
expect "a PR merges: the table shows yellow -> green" "$OUT" '^A +yellow -> green +all PRs merged'
eq "  and it is written" "$(status_of A)" green

# ---- gh failure: stale, exit 1, never green ---------------------------------------------
new_world stale "{$W:{\"prs\":{\"1\":\"OPEN\"}},\"fullbay/gadgets\":{\"prs\":{\"7\":\"MERGED\"}}}"
plan '[{"id":"W","prs":["fullbay/widgets#1"]},
       {"id":"G","prs":["fullbay/gadgets#7"],"repos":[{"name":"gadgets","exists":true}]}]'
run "$P" --write
rc_is "baseline: exit 0" "$RC" 0
eq "  W yellow" "$(status_of W)" yellow
eq "  G green" "$(status_of G)" green
echo "{$W:{\"fail\":true},\"fullbay/gadgets\":{\"prs\":{\"7\":\"MERGED\"}}}" > "$STUB_DIR/world.json"
run "$P" --write
rc_is "gh fails for one repo: exit 1" "$RC" 1
eq "  the step in that repo keeps its previous status" "$(status_of W)" yellow
eq "  and is flagged stale" "$(pj "d['steps'][0].get('stale')")" True
expect "  statusWhy says why" "$(pj "d['steps'][0]['statusWhy']")" '^stale: gh api graphql failed for fullbay/widgets: gh: HTTP 502 boom'
expect "  the table marks it stale" "$OUT" '^W +yellow -> yellow \(stale\)'
expect "  a stale warning is listed" "$OUT" 'W: status is stale'
eq "  the other repo is still scored" "$(status_of G)" green
eq "  and is not stale" "$(pj "d['steps'][1].get('stale')")" None
echo "{$W:{\"prs\":{\"1\":\"OPEN\"}},\"fullbay/gadgets\":{\"prs\":{\"7\":\"MERGED\"}}}" > "$STUB_DIR/world.json"
run "$P" --write
rc_is "gh recovers: exit 0" "$RC" 0
eq "  the stale flag is cleared" "$(pj "'stale' in d['steps'][0]")" False

new_world stale_none "{$W:{\"fail\":true}}"
plan '[{"id":"N","prs":["fullbay/widgets#1"]}]'
run "$P" --write
rc_is "gh fails and there is no previous status: exit 1" "$RC" 1
eq "  the step is red and stale, never green" "$(pj "(d['steps'][0]['status'], d['steps'][0]['stale'])")" "('red', True)"

new_world stale_green "{$W:{\"prs\":{\"1\":\"MERGED\"}}}"
plan '[{"id":"N","prs":["fullbay/widgets#1"]}]'
run "$P" --write
echo "{$W:{\"fail\":true}}" > "$STUB_DIR/world.json"
run "$P" --write
eq "  its PR was stored as MERGED by the first run" "$(pj "d['steps'][0]['prStates']")" "{'fullbay/widgets#1': 'MERGED'}"
eq "a stale step keeps green when every unreadable PR was last seen merged" "$(pj "(d['steps'][0]['status'], d['steps'][0]['stale'])")" "('green', True)"
run "$P" --write
eq "  and still does on the next failing run (the stored states survive a stale write)" "$(pj "(d['steps'][0]['status'], d['steps'][0]['prStates'])")" "('green', {'fullbay/widgets#1': 'MERGED'})"

# A stale green is only kept when every unreadable PR was seen merged; otherwise yellow, still stale.
new_world stale_dg "{$W:{\"fail\":true}}"
plan '[{"id":"NS","status":"green","prs":["fullbay/widgets#1"]},
       {"id":"OP","status":"green","prs":["fullbay/widgets#1"],"prStates":{"fullbay/widgets#1":"OPEN"}},
       {"id":"HALF","status":"green","prs":["fullbay/widgets#1","fullbay/widgets#2"],"prStates":{"fullbay/widgets#1":"MERGED"}},
       {"id":"BOTH","status":"green","prs":["fullbay/widgets#1","fullbay/widgets#2"],"prStates":{"fullbay/widgets#1":"MERGED","fullbay/widgets#2":"MERGED"}},
       {"id":"YEL","status":"yellow","prs":["fullbay/widgets#1"],"prStates":{"fullbay/widgets#1":"OPEN"}},
       {"id":"RED","status":"red","prs":["fullbay/widgets#1"]}]'
run "$P" --write
eq "a green step whose PR state was never stored drops to yellow, stale" "$(pj "(d['steps'][0]['status'], d['steps'][0]['stale'])")" "('yellow', True)"
eq "  a green step whose PR was last seen OPEN drops to yellow, stale" "$(pj "(d['steps'][1]['status'], d['steps'][1]['stale'])")" "('yellow', True)"
eq "  one of two unreadable PRs never seen merged: yellow, stale" "$(pj "(d['steps'][2]['status'], d['steps'][2]['stale'])")" "('yellow', True)"
eq "  both seen merged: green, stale" "$(pj "(d['steps'][3]['status'], d['steps'][3]['stale'])")" "('green', True)"
eq "  a yellow step stays yellow, stale" "$(pj "(d['steps'][4]['status'], d['steps'][4]['stale'])")" "('yellow', True)"
eq "  a red step stays red, stale" "$(pj "(d['steps'][5]['status'], d['steps'][5]['stale'])")" "('red', True)"
expect "  the table shows green -> yellow (stale)" "$OUT" '^NS +green -> yellow \(stale\)'

# The readable half of a stale green matters too: a readable PR that is not merged now drops it.
new_world stale_ro "{$W:{\"fail\":true},\"fullbay/gadgets\":{\"prs\":{\"7\":\"OPEN\",\"8\":\"MERGED\"}}}"
plan '[{"id":"RO","status":"green","prs":["fullbay/widgets#1","fullbay/gadgets#7"],"repos":[{"name":"widgets","exists":true},{"name":"gadgets","exists":true}],"prStates":{"fullbay/widgets#1":"MERGED","fullbay/gadgets#7":"MERGED"}},
       {"id":"RM","status":"green","prs":["fullbay/widgets#1","fullbay/gadgets#8"],"repos":[{"name":"widgets","exists":true},{"name":"gadgets","exists":true}],"prStates":{"fullbay/widgets#1":"MERGED","fullbay/gadgets#8":"MERGED"}}]'
run "$P" --write
eq "a stale green with a readable PR now OPEN drops to yellow, though the unreadable one was merged" "$(pj "(d['steps'][0]['status'], d['steps'][0]['stale'])")" "('yellow', True)"
eq "  a readable PR still merged and an unreadable one last seen merged: green, stale" "$(pj "(d['steps'][1]['status'], d['steps'][1]['stale'])")" "('green', True)"

new_world missing_repo "{}"
plan '[{"id":"N","prs":["fullbay/widgets#1"]}]'
run "$P" --write
rc_is "a repo GitHub cannot resolve: exit 1" "$RC" 1
expect "  names the error" "$OUT" 'Could not resolve to a Repository'

new_world missing_pr "{$W:{\"prs\":{\"1\":\"MERGED\"}}}"
plan '[{"id":"N","prs":["fullbay/widgets#1","fullbay/widgets#99"]},{"id":"M","prs":["fullbay/widgets#1"]}]'
run "$P" --write
rc_is "a named PR that does not exist: exit 1" "$RC" 1
expect "  the step is stale and names the PR" "$(pj "d['steps'][0]['statusWhy']")" 'PR fullbay/widgets#99 not found'
eq "  the step is not green" "$(status_of N)" red
eq "  a step with only existing PRs is still scored" "$(status_of M)" green

new_world stale_gate "{$W:{\"fail\":true}}"
plan '[{"id":"G","prs":["fullbay/widgets#1"],"designGate":{"required":true,"reason":"r"}},
       {"id":"D","doneWhen":"manual","done":true,"prs":["fullbay/widgets#1"]}]'
run "$P" --write
rc_is "gh fails: still exit 1 even when the affected steps need no gh answer" "$RC" 1
eq "  an unapproved gate is still orange (needs no PR state)" "$(status_of G)" orange
eq "  a manual done step is still green" "$(status_of D)" green
expect "  the unreadable PR is on stderr with its error" "$ERR" 'PR state unknown: fullbay/widgets#1: gh api graphql failed for fullbay/widgets: gh: HTTP 502 boom'
expect "  and is listed once as a warning in the output" "$OUT" '^  - PR state unknown: fullbay/widgets#1 \(gh api graphql failed'
eq "  and once in the plan's warnings, though two steps name it" "$(pj "sum(1 for w in d['warnings'] if w.startswith('PR state unknown: fullbay/widgets#1 '))")" 1
reject "  an unreadable PR is not reported as a PR before design approval" "$OUT" 'PR before design approval'

new_world gate_mixed "{$W:{\"prs\":{\"1\":\"OPEN\"}},\"fullbay/gadgets\":{\"fail\":true}}"
plan '[{"id":"G","prs":["fullbay/widgets#1","fullbay/gadgets#7"],"repos":[{"name":"widgets","exists":true},{"name":"gadgets","exists":true}],"designGate":{"required":true,"reason":"r"}},
       {"id":"U","prs":["fullbay/gadgets#7"],"designGate":{"required":true,"reason":"r"}}]'
run "$P" --write
rc_is "a gated step with one readable and one unreadable PR: exit 1" "$RC" 1
expect "  the readable PR still warns before approval, naming only it" "$OUT" 'G: PR before design approval \(fullbay/widgets#1\)'
expect "  the unreadable one is reported unknown" "$OUT" 'PR state unknown: fullbay/gadgets#7'
reject "  a gated step with only an unreadable PR gets no before-approval warning" "$OUT" 'U: PR before design approval'

OUT=$(cd "$WORK" && GH="$WORK/no-such-gh" "$STATUS" "$P" 2>&1); RC=$?
rc_is "gh not installed: exit 1, not a traceback" "$RC" 1
reject "  no traceback" "$OUT" 'Traceback'

# ---- validation: exit 2 naming the field -------------------------------------------------
new_world invalid
plan '[{"id":"A"}]'
cp "$P" "$STUB_DIR/good.json"
bad_plan() {  # LABEL FIELD-REGEX: the plan at $P must exit 2, name the field, call no gh, and stay unwritten
  cp "$P" "$STUB_DIR/before.json"
  run "$P" --write
  rc_is "$1: exit 2" "$RC" 2
  expect "  names the field" "$ERR" "$2"
  reject "  prints no table" "$OUT" '.'
  if [ -f "$STUB_DIR/calls.log" ]; then bad "  gh was called" "$(calls)"; else ok "  gh was not called"; fi
  if cmp -s "$P" "$STUB_DIR/before.json"; then ok "  the plan file was not written"; else bad "  plan file changed" ""; fi
}
plan '[{"id":"A","dependsOn":["B"]},{"id":"B","dependsOn":["A"]}]'
bad_plan "a dependency cycle" 'dependency cycle: A -> B -> A'
plan '[{"id":"A","dependsOn":["B"]},{"id":"B","dependsOn":["C"]},{"id":"C","dependsOn":["A"]}]'
bad_plan "a three-step cycle" 'dependency cycle: A -> B -> C -> A'
plan '[{"id":"A","dependsOn":["A"]}]'
bad_plan "a step depending on itself" 'steps\[0\]\.dependsOn\[0\]: step .A. depends on itself'
plan '[{"id":"A","dependsOn":["Z"]}]'
bad_plan "a missing dependency" "steps\[0\]\.dependsOn\[0\]: unknown step 'Z'"
plan '[{"id":"A"},{"id":"A"}]'
bad_plan "a duplicate step id" "steps\[1\]\.id: duplicate step id 'A'"
plan '[{"id":"A","prs":["widgets#4"]}]'
bad_plan "a PR ref without an owner" 'steps\[0\]\.prs\[0\]'
plan '[{"id":"A","prs":["fullbay/widgets#0"]}]'
bad_plan "a PR ref with number 0" 'steps\[0\]\.prs\[0\]'
plan '[{"id":"A","prs":["https://github.com/fullbay/widgets/pull/4"]}]'
bad_plan "a PR URL instead of owner/repo#N" 'steps\[0\]\.prs\[0\]'
plan '[{"id":"A","tickets":["zz-1"]}]'
bad_plan "a malformed ticket key" 'steps\[0\]\.tickets\[0\]'
plan '[{"id":"A","phase":"nope"}]'
bad_plan "a step in an unknown phase" "steps\[0\]\.phase: unknown phase 'nope'"
plan '[{"id":"A","dependOn":["B"]}]'
bad_plan "a misspelled field" 'steps\[0\]\.dependOn: is not a known field'
plan '[{"id":"A","doneWhen":"deployed"}]'
bad_plan "a bad doneWhen" 'steps\[0\]\.doneWhen'
plan '[{"id":"A","designGate":{"required":true}}]'
bad_plan "a required gate without a reason" 'steps\[0\]\.designGate\.reason'
plan '[{"id":"A","designGate":{"required":"yes","reason":"r"}}]'
bad_plan "a non-boolean gate flag" 'steps\[0\]\.designGate\.required: must be true or false'
plan '[{"id":"A","status":"purple"}]'
bad_plan "a bad status value" 'steps\[0\]\.status'
plan '[{"id":"A","repos":[{"name":"widgets"}]}]'
bad_plan "a repo without exists" 'steps\[0\]\.repos\[0\]\.exists: is required'
plan '[{"id":"A"}]' '[{"id":"q1","question":"?","blocks":["Z"],"status":"open"}]'
bad_plan "a question blocking an unknown step" "questions\[0\]\.blocks\[0\]: unknown step 'Z'"
plan '[{"id":"A"}]' '[{"id":"q1","question":"?","blocks":["A"],"status":"resolved"}]'
bad_plan "a resolved question with no answer" 'questions\[0\]\.answer'
plan '[{"id":"A"}]' '[{"id":"q1","question":"?","blocks":[["A"]],"status":"open"}]'
bad_plan "a question block that is a nested list (exit 2, not a TypeError)" 'questions\[0\]\.blocks\[0\]: must be a string'
plan '[{"id":"A"}]' '[{"id":"q1","question":"?","blocks":[{"x":1}],"status":"open"}]'
bad_plan "a question block that is an object" 'questions\[0\]\.blocks\[0\]: must be a string'
plan '[{"id":"A"}]' '[{"id":"q1","question":"?","blocks":["A","A"],"status":"open"}]'
bad_plan "a question blocking the same step twice" 'questions\[0\]\.blocks: has duplicate entries'
plan '[{"id":"A"}]' '[{"id":"q1","question":"?","blocks":[],"status":"maybe"}]'
bad_plan "a bad question status" 'questions\[0\]\.status'
python3 - "$P" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1])); del d["steps"][0]["plain"]; json.dump(d, open(sys.argv[1], "w"))
EOF
bad_plan "a step missing a required field" 'steps\[0\]\.plain: is required'
python3 - "$P" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1])); d["plan"]["source"]["kind"] = "wiki"; json.dump(d, open(sys.argv[1], "w"))
EOF
bad_plan "a bad source kind" 'plan\.source\.kind'
echo '{not json' > "$P"
bad_plan "invalid JSON" 'not valid JSON'
rm -f "$P"
run "$P"
rc_is "a missing file: exit 2" "$RC" 2
expect "  says it cannot read it" "$ERR" 'cannot read'
run
rc_is "no arguments: usage, exit 2" "$RC" 2

# ---- --write refuses to overwrite a plan that changed since it was read ---------------------
new_world race "{$W:{\"prs\":{\"1\":\"OPEN\"}}}"
plan '[{"id":"A","prs":["fullbay/widgets#1"]}]'
cat > "$WORK/gh-race" <<'EOS'
#!/bin/bash
# Edit the plan while the script is talking to gh, then answer like the normal stub.
python3 - "$RACE_PLAN" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["plan"]["title"] = "Edited meanwhile"; json.dump(d, open(sys.argv[1], "w"), indent=2)
PY
exec "$RACE_STUB" "$@"
EOS
chmod +x "$WORK/gh-race"
OUT=$(cd "$WORK" && GH="$WORK/gh-race" RACE_PLAN="$P" RACE_STUB="$STUB" "$STATUS" "$P" --write 2>"$STUB_DIR/err.txt"); RC=$?
ERR=$(cat "$STUB_DIR/err.txt")
rc_is "the plan changed after it was read: --write exits 2" "$RC" 2
expect "  says so and that nothing was written" "$ERR" 'changed since it was read; nothing was written'
eq "  the concurrent edit survives" "$(pj "d['plan']['title']")" "Edited meanwhile"
eq "  and no status was written" "$(pj "'status' in d['steps'][0]")" False
eq "  no temp file is left behind" "$(find "$STUB_DIR" -name '.impl-plan-*' | wc -l | tr -d ' ')" 0
run "$P" --write
rc_is "  a rerun on the edited plan writes normally" "$RC" 0
eq "  and scores it" "$(status_of A)" yellow

# ---- warnings ----------------------------------------------------------------------------
new_world warn "{$W:{\"prs\":{\"1\":\"MERGED\",\"2\":\"OPEN\"}}}"
plan '[{"id":"R"},
       {"id":"O","designGate":{"required":true,"reason":"r"}},
       {"id":"G1","prs":["fullbay/widgets#1"],"dependsOn":["R"]},
       {"id":"Y1","prs":["fullbay/widgets#2"],"dependsOn":["O"]},
       {"id":"G2","prs":["fullbay/widgets#1"]},
       {"id":"Y2","prs":["fullbay/widgets#2"],"dependsOn":["G2"]},
       {"id":"R2","dependsOn":["R"]},
       {"id":"O2","designGate":{"required":true,"reason":"r"},"dependsOn":["R"]}]' \
     '[{"id":"q1","question":"Which?","blocks":["R","Y2"],"status":"open"},
       {"id":"q2","question":"Gate?","blocks":["O"],"status":"open"},
       {"id":"q3","question":"Done?","blocks":["G2"],"status":"resolved","answer":"yes"}]'
run "$P" --write
expect "green with a red dependency warns" "$OUT" 'G1 is green but depends on R, which is red'
expect "yellow with an orange dependency warns" "$OUT" 'Y1 is yellow but depends on O, which is orange'
reject "yellow on a green dependency: no warning" "$OUT" 'Y2 is yellow but depends'
reject "red on a red dependency: no warning" "$OUT" 'R2 is red but depends'
reject "orange on a red dependency: no warning" "$OUT" 'O2 is orange but depends'
expect "an open question blocking a yellow step warns" "$OUT" 'open question q1 blocks Y2, which is yellow'
reject "an open question blocking a red step: no warning" "$OUT" 'open question q1 blocks R,'
expect "an open question blocking an orange step warns" "$OUT" 'open question q2 blocks O, which is orange'
reject "a resolved question never warns" "$OUT" 'question q3'
eq "the warnings are written to the plan" "$(pj "len(d['warnings'])")" 4

# ---- --discover --------------------------------------------------------------------------
new_world disc "{$W:{\"prs\":{\"1\":\"OPEN\"},\"prs-list\":[
  {\"number\":1,\"title\":\"ZZ-1 linked already\",\"headRefName\":\"feat/zz-1\",\"state\":\"OPEN\"},
  {\"number\":2,\"title\":\"ZZ-1 add the thing\",\"headRefName\":\"x\",\"state\":\"OPEN\"},
  {\"number\":3,\"title\":\"unrelated words\",\"headRefName\":\"feature/zz-2-by-branch\",\"state\":\"MERGED\"},
  {\"number\":4,\"title\":\"ZZ-12 is a longer key\",\"headRefName\":\"y\",\"state\":\"OPEN\"},
  {\"number\":5,\"title\":\"AZZ-2 nor this\",\"headRefName\":\"y\",\"state\":\"OPEN\"},
  {\"number\":6,\"title\":\"nothing\",\"headRefName\":\"y\",\"state\":\"OPEN\"}]},
  \"fullbay/gizmos\":{\"prs-list\":[{\"number\":9,\"title\":\"zz-2 in another repo\",\"headRefName\":\"y\",\"state\":\"CLOSED\"}]}}"
plan '[{"id":"A","tickets":["ZZ-1","ZZ-2"],"prs":["fullbay/widgets#1"],"repos":[{"name":"widgets","exists":true},{"name":"gizmos","exists":true},{"name":"newrepo","exists":false}]},
       {"id":"B","tickets":["ZZ-3"]},
       {"id":"C"}]'
cp "$P" "$STUB_DIR/orig.json"
run "$P"
reject "without --discover nothing is searched" "$(calls)" '^discover'
run "$P" --discover
rc_is "--discover: exit 0" "$RC" 0
expect "a PR whose title names the key is suggested" "$OUT" 'step A: fullbay/widgets#2 \[OPEN\] "ZZ-1 add the thing" matches ZZ-1'
expect "a PR whose branch names the key is suggested (case-insensitive)" "$OUT" 'step A: fullbay/widgets#3 \[MERGED\].*matches ZZ-2'
expect "another repo of the step is searched too" "$OUT" 'step A: fullbay/gizmos#9 \[CLOSED\]'
reject "a PR the plan already links is not suggested" "$OUT" 'widgets#1 \['
reject "ZZ-12 is not ZZ-1" "$OUT" 'widgets#4'
reject "AZZ-2 is not ZZ-2" "$OUT" 'widgets#5'
reject "a PR naming no key is not suggested" "$OUT" 'widgets#6'
reject "a repo that does not exist yet is not searched" "$(calls)" 'newrepo'
reject "a step with no tickets suggests nothing" "$OUT" 'step [BC]:'
eq "each repo is searched once" "$(calls | grep -c '^discover fullbay/widgets')" 1
if cmp -s "$P" "$STUB_DIR/orig.json"; then ok "suggestions never touch the plan"; else bad "plan changed by --discover" ""; fi
run "$P" --discover --write
eq "even with --write the PR list is unchanged" "$(pj "d['steps'][0]['prs']")" "['fullbay/widgets#1']"
new_world disc_none "{$W:{\"prs-list\":[{\"number\":6,\"title\":\"nothing\",\"headRefName\":\"y\",\"state\":\"OPEN\"}]}}"
plan '[{"id":"A","tickets":["ZZ-1"]}]'
run "$P" --discover
expect "no matches says so" "$OUT" 'discover: no unlinked PRs'

new_world disc_pages "{$W:{\"pages\":[[{\"number\":1,\"title\":\"nope\",\"headRefName\":\"a\",\"state\":\"OPEN\"}],[{\"number\":2,\"title\":\"ZZ-1 later page\",\"headRefName\":\"a\",\"state\":\"OPEN\"}]]}}"
plan '[{"id":"A","tickets":["ZZ-1"]}]'
run "$P" --discover
expect "a match on the second page is found" "$OUT" 'widgets#2 \[OPEN\]'
expect "  the second page was requested with the cursor" "$(calls)" 'discover fullbay/widgets after=1'

new_world disc_cut
python3 - <<'EOF' > "$STUB_DIR/world.json"
import json
pages = [[{"number": p * 10 + i + 1, "title": "x", "headRefName": "y", "state": "OPEN"} for i in range(3)] for p in range(7)]
print(json.dumps({"fullbay/widgets": {"pages": pages}}))
EOF
plan '[{"id":"A","tickets":["ZZ-1"]}]'
run "$P" --discover
expect "a long PR history warns that discovery stopped early" "$OUT" 'discovery in fullbay/widgets looked only at its 15 most recently updated PRs'
eq "  after the page cap" "$(calls | grep -c '^discover')" 5

new_world disc_fail "{$W:{\"fail\":true}}"
plan '[{"id":"A","tickets":["ZZ-1"]}]'
run "$P" --discover
rc_is "a repo that cannot be searched: exit 1, loudly" "$RC" 1
expect "  says which" "$ERR" 'discovery failed: .*fullbay/widgets'

new_world disc_case "{\"Fullbay/Widgets\":{\"prs\":{\"1\":\"OPEN\"}},$W:{\"prs\":{\"1\":\"OPEN\"},\"prs-list\":[
  {\"number\":1,\"title\":\"ZZ-1 linked, other case\",\"headRefName\":\"a\",\"state\":\"OPEN\"},
  {\"number\":2,\"title\":\"ZZ-1 unlinked\",\"headRefName\":\"a\",\"state\":\"OPEN\"}]}}"
plan '[{"id":"A","tickets":["ZZ-1"],"prs":["Fullbay/Widgets#1"]}]'
run "$P" --discover
rc_is "a PR linked with different owner/repo case: exit 0" "$RC" 0
reject "  is not suggested again" "$OUT" 'widgets#1 \['
expect "  an unlinked one still is" "$OUT" 'fullbay/widgets#2 \[OPEN\]'
plan '[{"id":"A","tickets":["ZZ-1"],"prs":["fullbay/widgets#1"],"repos":[{"name":"widgets","exists":true},{"name":"Fullbay/Widgets","exists":true}]}]'
rm -f "$STUB_DIR/calls.log"
run "$P" --discover
eq "  and the same repo spelled in two cases is searched once" "$(calls | grep -c '^discover')" 1

# ---- owners ------------------------------------------------------------------------------
new_world org "{\"acme/widgets\":{\"prs-list\":[{\"number\":3,\"title\":\"ZZ-1\",\"headRefName\":\"a\",\"state\":\"OPEN\"}]},\"fullbay/gadgets\":{\"prs-list\":[]}}"
plan '[{"id":"A","tickets":["ZZ-1"],"repos":[{"name":"acme/widgets","exists":true},{"name":"gadgets","exists":true}]}]'
run "$P" --discover
expect "an owner in the repo name is used" "$OUT" 'acme/widgets#3'
expect "a bare repo name defaults to the fullbay org" "$(calls)" '^discover fullbay/gadgets'
new_world org2 "{\"acme/gadgets\":{\"prs-list\":[]}}"
plan '[{"id":"A","tickets":["ZZ-1"],"repos":[{"name":"gadgets","exists":true}]}]'
run "$P" --discover --org acme
expect "--org changes the default owner" "$(calls)" '^discover acme/gadgets'

echo
echo "impl-plan-status: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
