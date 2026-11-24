#!/bin/bash
#
# Tests for impl-plan-render. The input is a synthetic scored plan.json (made-up repos and
# ticket keys: widgets, gadgets, ZZ-<n>); the output page is checked as text and with a
# small HTML parser. Nothing here touches the network.
#
# Usage: bin/tests/impl-plan-render.sh        (exit 1 if any case fails)

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
RENDER="$HERE/../impl-plan-render"
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

ok()  { PASS=$((PASS + 1)); echo "ok    $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL  $1"; echo "      got: $(printf '%s' "$2" | head -c 400)"; }
expect() { if printf '%s\n' "$2" | grep -Eq -- "$3"; then ok "$1"; else bad "$1 (wanted /$3/)" "$2"; fi; }
reject() { if printf '%s\n' "$2" | grep -Eq -- "$3"; then bad "$1 (did not want /$3/)" "$2"; else ok "$1"; fi; }
has()    { if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1"; else bad "$1 (wanted '$3')" "$2"; fi; }
lacks()  { if printf '%s' "$2" | grep -qF -- "$3"; then bad "$1 (did not want '$3')" "$2"; else ok "$1"; fi; }
rc_is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (wanted exit $3)" "exit $2"; fi; }

# gen.py OUT [variant]: the fixture plan. It covers all four statuses, every chip kind, a
# stale step, open and resolved questions, warnings, and hostile strings in every text field.
cat > "$WORK/gen.py" <<'EOS'
import json, sys
variant = sys.argv[2] if len(sys.argv) > 2 else "full"
evil = '<script>alert(1)</script> "q" & <img src=x onerror=alert(2)>'
def step(i, status, **kw):
    d = {"id": i, "phase": "p1", "title": "Step " + i, "work": "Work for " + i, "plain": "Plain for " + i,
         "repos": [{"name": "widgets", "exists": True}], "status": status, "statusWhy": "why " + i}
    d.update(kw)
    return d
steps = [
    step("A1", "green", title="Done thing", tickets=["ZZ-1", "ZZ-2"], prs=["fullbay/widgets#11", "fullbay/widgets#12"],
         prStates={"fullbay/widgets#11": "MERGED", "fullbay/widgets#12": "MERGED"},
         work="First paragraph with `code <b>`.\n\nSecond paragraph.\n- item one\n- item <two>",
         statusNote="Note " + evil),
    step("A2", "yellow", title="PR out thing", prs=["fullbay/widgets#13", "fullbay/widgets#14"],
         prStates={"fullbay/widgets#13": "OPEN", "fullbay/widgets#14": "CLOSED"}, dependsOn=["A1"],
         prerequisites=["Prereq one", "Prereq `two`"], stale=True),
    step("B1", "orange", phase="p2", title="Gate thing",
         designGate={"required": True, "reason": "new mechanism touching durable state", "approved": None},
         repos=[{"name": "gizmos", "exists": False}, {"name": "acme/widgets", "exists": True}], dependsOn=["A2", "A1"]),
    step("B2", "orange", phase="p2", title="Approved gate", designGate={"required": True, "reason": "r", "approved": "2026-11-02"}),
    step("B3", "red", phase="p2", title="Not started thing", dependsOn=["B1"]),
    step("E1", "red", phase="p3", title=evil, work=evil, plain=evil, prerequisites=[evil], statusNote=evil,
         designGate={"required": False}, repos=[{"name": "widgets", "exists": True}]),
]
doc = {"plan": {"title": "Fixture <Plan> & \"co\"", "slug": "fixture", "source": {"kind": "tds", "ref": "domains/x/tds/y.md"},
                "summary": "Summary " + evil, "epics": ["ZZ-100"], "updatedAt": "2026-11-24",
                "decisions": [{"title": "Decision " + evil, "detail": "Detail `x` " + evil}]},
       "phases": [{"id": "p1", "title": "Phase one", "note": "note one"}, {"id": "p2", "title": "Phase two"},
                  {"id": "p3", "title": "Phase <three>"}, {"id": "p4", "title": "Empty phase"}],
       "steps": steps,
       "questions": [
           {"id": "q1", "question": "Open one? " + evil, "blocks": ["B1", "B3"], "owner": "Someone", "status": "open"},
           {"id": "q2", "question": "Resolved one?", "blocks": ["A1"], "status": "resolved", "answer": "Answer " + evil},
           {"id": "q3", "question": "Open two?", "blocks": [], "status": "open"}],
       "warnings": ["B3 is red but " + evil, "second warning"]}
if variant == "bare":
    doc["plan"] = {"title": "Bare", "slug": "bare", "source": {"kind": "session", "ref": ""}, "summary": "s"}
    doc["phases"] = [{"id": "p1", "title": "P"}]
    doc["steps"] = [step("A", "red")]
    doc["questions"] = []
    del doc["warnings"]
if variant == "nostatus":
    del doc["steps"][0]["status"]
json.dump(doc, open(sys.argv[1], "w"), indent=2)
EOS

# check.py HTML: well-formed enough (tags balance), ids unique, every #anchor has a target.
cat > "$WORK/check.py" <<'EOS'
import sys
from html.parser import HTMLParser
VOID = {"meta", "link", "br", "img", "hr", "input"}
class P(HTMLParser):
    def __init__(self):
        super().__init__(); self.stack = []; self.ids = []; self.hrefs = []; self.errors = []
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if "id" in a: self.ids.append(a["id"])
        if a.get("href", "").startswith("#"): self.hrefs.append(a["href"][1:])
        if tag not in VOID: self.stack.append(tag)
    def handle_endtag(self, tag):
        if not self.stack or self.stack[-1] != tag: self.errors.append("unbalanced </%s> over %s" % (tag, self.stack[-3:]))
        else: self.stack.pop()
p = P(); p.feed(open(sys.argv[1]).read())
errs = p.errors + (["unclosed: %s" % p.stack] if p.stack else [])
dups = sorted({i for i in p.ids if p.ids.count(i) > 1})
if dups: errs.append("duplicate ids %s" % dups)
missing = sorted({h for h in p.hrefs if h not in p.ids})
if missing: errs.append("dangling anchors %s" % missing)
print("; ".join(errs) if errs else "clean")
EOS

render() {  # PLAN -> OUT (stdout), ERR (stderr), RC
  OUT=$("$RENDER" "$1" 2>"$WORK/err.txt"); RC=$?
  ERR=$(cat "$WORK/err.txt")
}

python3 "$WORK/gen.py" "$WORK/plan.json"
render "$WORK/plan.json"
printf '%s' "$OUT" > "$WORK/index.html"
rc_is "renders a scored plan: exit 0" "$RC" 0
expect "stdout is a fragment that starts with <title>" "$OUT" '^<title>'
reject "no doctype, html, head or body tags (the publisher supplies them)" "$OUT" '<!doctype|</?(html|head|body)[ >]'
if [ "$(printf '%s' "$OUT" | grep -bo '</title>' | head -1 | cut -d: -f1)" -lt 8192 ] 2>/dev/null; then ok "<title> sits within the first 8KB"; else bad "<title> past 8KB" ""; fi
has "viewport-fit-sides meta" "$OUT" '<meta name="claude:viewport-fit-sides" content="cover">'
reject "no charset or viewport meta of its own" "$OUT" '<meta (charset|name="viewport")'
has "<title> is the plan title, escaped" "$OUT" '<title>Fixture &lt;Plan&gt; &amp; &quot;co&quot;</title>'
if [ "$(python3 "$WORK/check.py" "$WORK/index.html")" = clean ]; then ok "markup balances, ids are unique, every #anchor has a target"; else bad "markup check" "$(python3 "$WORK/check.py" "$WORK/index.html")"; fi
a=$("$RENDER" "$WORK/plan.json"); b=$("$RENDER" "$WORK/plan.json")
if [ "$a" = "$b" ]; then ok "rendering twice gives identical output"; else bad "non-deterministic output" ""; fi

# ---- no scripts, theme tokens --------------------------------------------------------
reject "no scripts" "$OUT" '<script'
reject "no external scripts or images" "$OUT" '(<img|<iframe| src=")'
if [ "$(printf '%s' "$OUT" | grep -o 'href="https\?://[^"]*"' | grep -vc -e 'github.com/' -e 'fullbay.atlassian.net/browse/' -e 'fonts.googleapis.com')" = 0 ]; then ok "external links are only GitHub, Jira and the fonts stylesheet"; else bad "unexpected external link" "$(printf '%s' "$OUT" | grep -o 'href="https\?://[^"]*"' | sort -u)"; fi
has "Google Fonts stylesheet" "$OUT" '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque'
has "IBM Plex in the font stack" "$OUT" 'IBM+Plex+Sans'
expect "light tokens under :root" "$(printf '%s' "$OUT" | tr -d '\n')" ':root\{[^}]*--ok:#2f6f3a'
has "dark tokens behind prefers-color-scheme, unless forced light" "$OUT" '@media (prefers-color-scheme: dark){:root:not([data-theme="light"]){'
has "forced dark theme block" "$OUT" ':root[data-theme="dark"]{'
expect "explicit body background" "$OUT" 'body\{[^}]*background:var\(--bg\)'
expect "orange gate token in light and dark" "$(printf '%s' "$OUT" | grep -c -e '--gate:#b8500a' -e '--gate:#f4a259')" '^3$'
reject "the purple gate colour is gone" "$OUT" '(7a2e8f|d39be4)'

# ---- phone width --------------------------------------------------------------------------
expect "16px gutter on the wrapper" "$OUT" '\.wrap\{[^}]*padding-left:max\(16px'
expect "  both sides" "$OUT" '\.wrap\{[^}]*padding-right:max\(16px'
expect "  the gutters respect the safe area (left)" "$OUT" '\.wrap\{[^}]*padding-left:max\(16px,env\(safe-area-inset-left,0px\)\)'
expect "  the gutters respect the safe area (right)" "$OUT" '\.wrap\{[^}]*padding-right:max\(16px,env\(safe-area-inset-right,0px\)\)'
expect "  vertical padding is padding-block, not a shorthand that resets the gutters" "$OUT" '\.wrap\{[^}]*padding-block:40px 64px'
reject "  no padding shorthand on .wrap" "$OUT" '\.wrap\{([^}]*;)?padding:'
has "the step grid collapses to one column on a phone" "$OUT" '@media (max-width:560px){'
expect "  the step grid column can shrink (minmax(0,1fr))" "$OUT" '\.step\{grid-template-columns:minmax\(0,1fr\)\}'
expect "chips wrap long refs instead of overflowing" "$OUT" '\.chip\{[^}]*overflow-wrap:anywhere'
expect "code wraps" "$OUT" 'code\{[^}]*overflow-wrap:anywhere'
reject "no fixed-width table or svg that forces a horizontal scroll" "$OUT" '(<table|<svg|min-width:[0-9]{3,}px)'

# ---- status colours: every class, border + soft background + pill text -------------------
for c in green yellow orange red; do
  has "step class s-$c is used" "$OUT" "class=\"step s-$c\""
done
has "green maps to --ok" "$OUT" '.step.s-green{border-left:5px solid var(--ok);background:var(--ok-soft)}'
has "yellow maps to --pr" "$OUT" '.step.s-yellow{border-left:5px solid var(--pr);background:var(--pr-soft)}'
has "orange maps to --gate" "$OUT" '.step.s-orange{border-left:5px solid var(--gate);background:var(--gate-soft)}'
has "red maps to --risk" "$OUT" '.step.s-red{border-left:5px solid var(--risk);background:var(--risk-soft)}'
has "pill text colour for green" "$OUT" '.s-green .spill{color:var(--ok);border-color:var(--ok)}'
has "pill text colour for yellow" "$OUT" '.s-yellow .spill{color:var(--pr-ink);border-color:var(--pr)}'
has "pill text colour for orange" "$OUT" '.s-orange .spill{color:var(--gate);border-color:var(--gate)}'
has "pill text colour for red" "$OUT" '.s-red .spill{color:var(--risk);border-color:var(--risk)}'
has "the pill says it in words: Completed" "$OUT" '<span class="spill">Completed</span>'
has "  PR out" "$OUT" '<span class="spill">PR out</span>'
has "  Design gate" "$OUT" '<span class="spill">Design gate</span>'
has "  Not started" "$OUT" '<span class="spill">Not started</span>'
expect "count strip: n green · n yellow · n orange · n red" "$(printf '%s' "$OUT" | sed 's/<[^>]*>/ /g' | tr -s ' ')" '1 green *· *1 yellow *· *2 orange *· *2 red'
has "legend names all four" "$OUT" 'Orange: design gate'
expect "  green, yellow and red" "$OUT" 'Green: completed.*Yellow: PR out.*Red: not started'
has "a stale step gets a stale pill" "$OUT" '<span class="spill stale">stale</span>'
has "statusWhy is shown" "$OUT" '<p class="why">why A1</p>'

# ---- content ------------------------------------------------------------------------------
has "summary" "$OUT" 'Summary &lt;script&gt;alert(1)&lt;/script&gt;'
has "decisions section" "$OUT" '<h2>What is decided</h2>'
has "decision detail with inline code" "$OUT" 'Detail <code>x</code> '
has "epic chip links to Jira" "$OUT" '<a class="chip t" href="https://fullbay.atlassian.net/browse/ZZ-100">ZZ-100</a>'
has "ticket chip links to Jira" "$OUT" 'href="https://fullbay.atlassian.net/browse/ZZ-2">ZZ-2</a>'
has "PR chip links to GitHub with its state" "$OUT" '<a class="chip pr prs-merged" href="https://github.com/fullbay/widgets/pull/11">fullbay/widgets#11 · merged</a>'
has "  an open PR" "$OUT" 'class="chip pr prs-open" href="https://github.com/fullbay/widgets/pull/13">fullbay/widgets#13 · open</a>'
has "  a closed PR" "$OUT" 'class="chip pr prs-closed" href="https://github.com/fullbay/widgets/pull/14">fullbay/widgets#14 · closed</a>'
has "a new repo gets a new chip" "$OUT" '<span class="chip">gizmos</span> <span class="chip new">new</span>'
lacks "an existing repo does not" "$OUT" '<span class="chip">widgets</span> <span class="chip new">'
has "an owner-qualified repo name is shown as given" "$OUT" '<span class="chip">acme/widgets</span>'
has "Depends on links are anchors to the step" "$OUT" '<a class="chip dep" href="#step-A2">A2</a><a class="chip dep" href="#step-A1">A1</a>'
has "  and the target exists" "$OUT" 'id="step-A1"'
has "Prerequisites list" "$OUT" '<dt>Prerequisites</dt><dd><ul><li>Prereq one</li><li>Prereq <code>two</code></li></ul></dd>'
has "a required gate shows a chip, not approved" "$OUT" '<span class="chip gate">design gate not approved</span>'
has "  approved with its date" "$OUT" '<span class="chip gate">design gate approved 2026-11-02</span>'
has "  and its reason" "$OUT" 'new mechanism touching durable state (not approved)'
has "work: paragraphs and code" "$OUT" '<p>First paragraph with <code>code &lt;b&gt;</code>.</p><p>Second paragraph.</p><ul><li>item one</li><li>item &lt;two&gt;</li></ul>'
has "Work, Repos, Plain English labels" "$OUT" '<dt>Plain English</dt>'
has "phase progress counts only completed steps" "$OUT" '1 of 2 completed'
has "  a phase with none completed" "$OUT" '0 of 3 completed'
has "an empty phase says so" "$OUT" 'No steps in this phase.'
has "an open question blocks steps: the step links to it" "$OUT" '<dt>Blocked by</dt><dd><div class="chips"><a class="chip dep" href="#q-q1">q1</a>'

# ---- open questions -----------------------------------------------------------------------
has "Open questions section" "$OUT" '<h2>Open questions</h2>'
expect "open questions come before the resolved details" "$(printf '%s' "$OUT" | tr -d '\n')" 'Open one\?.*Open two\?.*<details><summary>Resolved \(1\)</summary>.*Resolved one\?'
has "an open question lists the steps it blocks" "$OUT" '<span class="owner">Blocks:</span><a class="chip dep" href="#step-B1">B1</a><a class="chip dep" href="#step-B3">B3</a>'
has "  and its owner" "$OUT" 'Owner: Someone'
has "a resolved question shows its answer, escaped" "$OUT" '<p><b>Answer:</b> Answer &lt;script&gt;'
expect "the resolved question is inside <details>" "$(printf '%s' "$OUT" | tr -d '\n')" '<details>.*Resolved one\?.*</details>'
lacks "an open question is not inside <details>" "$(printf '%s' "$OUT" | tr -d '\n' | sed 's/<details>.*<\/details>//')" 'Resolved one?'

# ---- warnings callout ---------------------------------------------------------------------
has "warnings are a callout" "$OUT" '<aside class="callout" role="note" aria-label="Warnings"><b>Warnings</b><ul><li>B3 is red but '
has "  every warning is listed" "$OUT" '<li>second warning</li>'

# ---- escaping -----------------------------------------------------------------------------
reject "no raw <script> from the plan" "$OUT" '<script'
reject "no raw <img> from the plan" "$OUT" '<img'
reject "no tag with an event-handler attribute can come out" "$OUT" '<[a-z][^>]* onerror='
has "hostile strings are escaped everywhere (title field)" "$OUT" '&lt;script&gt;alert(1)&lt;/script&gt; &quot;q&quot; &amp; &lt;img src=x onerror=alert(2)&gt;'
reject "the raw hostile string never appears" "$OUT" '<script>alert'
expect "the escaped hostile string appears in every text field (>= 12 times)" "$([ "$(printf '%s' "$OUT" | grep -o '&lt;script&gt;alert(1)' | wc -l)" -ge 12 ] && echo yes)" '^yes$'

# ---- bare plan and failures ---------------------------------------------------------------
python3 "$WORK/gen.py" "$WORK/bare.json" bare
render "$WORK/bare.json"
rc_is "a minimal plan renders: exit 0" "$RC" 0
has "  no decisions section" "$OUT" '<section><h2>Where it stands</h2>'
lacks "  and no decisions heading" "$OUT" 'What is decided'
lacks "  no warnings callout" "$OUT" 'class="callout"'
has "  no open questions says so" "$OUT" '<p>No open questions.</p>'
lacks "  no resolved details" "$OUT" '<details>'

python3 "$WORK/gen.py" "$WORK/nostatus.json" nostatus
render "$WORK/nostatus.json"
rc_is "a step with no status: exit 2" "$RC" 2
has "  names the field and the fix" "$ERR" 'steps[0].status: is missing; run impl-plan-status --write first'
if [ -z "$OUT" ]; then ok "  prints no page"; else bad "  printed a page" "$OUT"; fi

python3 - "$WORK/plan.json" "$WORK/cycle.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1])); d["steps"][0]["dependsOn"] = ["A2"]; json.dump(d, open(sys.argv[2], "w"))
EOF
render "$WORK/cycle.json"
rc_is "an invalid plan (cycle): exit 2" "$RC" 2
has "  uses the shared validator" "$ERR" 'dependency cycle'
python3 - "$WORK/plan.json" "$WORK/nested.json" "$WORK/dup.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1])); d["questions"][0]["blocks"] = [["B1"]]; json.dump(d, open(sys.argv[2], "w"))
d["questions"][0]["blocks"] = ["B1", "B1"]; json.dump(d, open(sys.argv[3], "w"))
EOF
render "$WORK/nested.json"
rc_is "a question block that is a nested list: exit 2, not a TypeError" "$RC" 2
has "  names the field" "$ERR" 'questions[0].blocks[0]: must be a string'
reject "  no traceback" "$ERR" 'Traceback'
render "$WORK/dup.json"
rc_is "a question blocking the same step twice: exit 2" "$RC" 2
has "  names the field" "$ERR" 'questions[0].blocks: has duplicate entries'
echo '{nope' > "$WORK/junk.json"
render "$WORK/junk.json"
rc_is "invalid JSON: exit 2" "$RC" 2
render "$WORK/missing.json"
rc_is "a missing file: exit 2" "$RC" 2
reject "  no traceback" "$ERR" 'Traceback'
OUT=$("$RENDER" 2>&1); RC=$?
rc_is "no arguments: usage, exit 2" "$RC" 2
if ls "$HERE"/../__pycache__ >/dev/null 2>&1; then bad "importing the validator left bytecode in bin/" "$(ls "$HERE"/../__pycache__)"; else ok "importing the validator leaves no bytecode in bin/"; fi

echo
echo "impl-plan-render: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
