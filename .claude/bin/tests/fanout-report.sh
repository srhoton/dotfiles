#!/bin/bash
#
# Tests for fanout-report. Synthetic review-fanout outputs only; no GitHub, no
# network. Each case writes an input file, runs the script with --out into a
# temp dir, and asserts on the exit code and the rendered markdown.
#
# Usage: bin/tests/fanout-report.sh        (exit 1 if any case fails)

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPORT="$HERE/../fanout-report"
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

RESULT='{
  "actionable": [
    {"severity": "CRITICAL", "file": "src/a.ts", "line": 10, "description": "first | pipe", "source": "functional", "verified": true, "verification": "confirmed at src/a.ts:10"},
    {"severity": "HIGH", "file": "src/b.ts", "line": 20, "description": "second finding", "source": "quality+adr", "verified": false}
  ],
  "informational": [
    {"severity": "MEDIUM", "file": "src/c.ts", "line": 5, "description": "minor thing", "source": "performance"}
  ],
  "refuted": [
    {"severity": "HIGH", "file": "src/d.ts", "line": 7, "description": "claimed bug", "source": "functional", "refutation": "guarded at src/d.ts:3 | so unreachable"}
  ],
  "reviewersSkipped": ["adr", "performance"]
}'

check() { # NAME CONDITION-EXIT-STATUS
  if [ "$2" -eq 0 ]; then PASS=$((PASS + 1)); echo "ok   $1"
  else FAIL=$((FAIL + 1)); echo "FAIL $1"; fi
}

has() { grep -qF -- "$2" "$1"; }

# --- wrapped workflow output ------------------------------------------------
printf '{"summary":"done","agentCount":7,"logs":["x"],"result":%s}' "$RESULT" > "$WORK/wrapped.json"
STDOUT=$("$REPORT" "$WORK/wrapped.json" --repo demo --out "$WORK/wrapped.md"); RC=$?
check "wrapped: exit 0" $((RC))
check "wrapped: stdout is path then counts line" $([ "$STDOUT" = "$WORK/wrapped.md
2 actionable, 1 refuted, 1 informational" ]; echo $?)
check "wrapped: title uses --repo" $(has "$WORK/wrapped.md" "# Review fan-out report: demo"; echo $?)
check "wrapped: skipped-reviewers warning" $(has "$WORK/wrapped.md" "WARNING: reviewers skipped (returned nothing or errored): adr, performance"; echo $?)
check "wrapped: actionable numbered [1]" $(has "$WORK/wrapped.md" "| [1] | CRITICAL | src/a.ts:10 | functional | yes |"; echo $?)
check "wrapped: actionable numbered [2], unverified shows NO" $(has "$WORK/wrapped.md" "| [2] | HIGH | src/b.ts:20 | quality+adr | NO | second finding |"; echo $?)
check "wrapped: pipe in description escaped" $(has "$WORK/wrapped.md" 'first \| pipe'; echo $?)
check "wrapped: pipe in refutation escaped" $(has "$WORK/wrapped.md" 'src/d.ts:3 \| so unreachable'; echo $?)
check "wrapped: section headings" $(grep -c -E '^## (Actionable \(CRITICAL/HIGH\)|Refuted by verification|Informational \(MEDIUM/LOW\))$' "$WORK/wrapped.md" | grep -qx 3; echo $?)
check "wrapped: verification detail for the verified finding" $(has "$WORK/wrapped.md" "- [1] verification: confirmed at src/a.ts:10"; echo $?)
check "wrapped: unverified finding flagged in detail block" $(has "$WORK/wrapped.md" "- [2] unverified"; echo $?)
check "wrapped: informational row" $(has "$WORK/wrapped.md" "| 1 | MEDIUM | src/c.ts:5 | performance | minor thing |"; echo $?)

# --- bare result ------------------------------------------------------------
printf '%s' "$RESULT" > "$WORK/bare.json"
STDOUT=$("$REPORT" "$WORK/bare.json" --repo demo --out "$WORK/bare.md"); RC=$?
check "bare: exit 0 and same counts" $([ "$RC" -eq 0 ] && [ "$(echo "$STDOUT" | tail -1)" = "2 actionable, 1 refuted, 1 informational" ]; echo $?)

# --- embedded in surrounding text -------------------------------------------
{ echo 'workflow log {not json} line'; echo 'Result follows:'; printf '{"summary":"s","result":%s}' "$RESULT"; echo; echo 'trailing {"other": 1} text'; } > "$WORK/embedded.txt"
STDOUT=$("$REPORT" "$WORK/embedded.txt" --repo demo --out "$WORK/embedded.md"); RC=$?
check "embedded: exit 0 and same counts" $([ "$RC" -eq 0 ] && [ "$(echo "$STDOUT" | tail -1)" = "2 actionable, 1 refuted, 1 informational" ]; echo $?)
check "embedded: findings rendered" $(has "$WORK/embedded.md" "| [1] | CRITICAL | src/a.ts:10 |"; echo $?)

# --- result carried as a JSON-encoded string -----------------------------------
python3 -c 'import json,sys; print(json.dumps({"summary":"s","result":sys.argv[1]}))' "$RESULT" > "$WORK/strres.json"
STDOUT=$("$REPORT" "$WORK/strres.json" --repo demo --out "$WORK/strres.md"); RC=$?
check "string-encoded result: exit 0 and same counts" $([ "$RC" -eq 0 ] && [ "$(echo "$STDOUT" | tail -1)" = "2 actionable, 1 refuted, 1 informational" ]; echo $?)

# --- --stdout prints the whole report ---------------------------------------
STDOUT=$("$REPORT" "$WORK/bare.json" --repo demo --out "$WORK/s.md" --stdout)
check "--stdout: whole report on stdout" $(echo "$STDOUT" | grep -qF "## Actionable (CRITICAL/HIGH)"; echo $?)

# --- empty sections and no skip warning --------------------------------------
echo '{"actionable":[],"informational":[],"refuted":[],"reviewersSkipped":[]}' > "$WORK/empty.json"
"$REPORT" "$WORK/empty.json" --repo demo --out "$WORK/empty.md" >/dev/null; RC=$?
check "empty: exit 0, no warning, _None._ placeholders" $([ "$RC" -eq 0 ] && ! has "$WORK/empty.md" WARNING && [ "$(grep -c '_None._' "$WORK/empty.md")" -eq 3 ]; echo $?)

# --- default path under HOME/.claude/scratch/<repo>/ ---------------------------
mkdir -p "$WORK/home"
STDOUT=$(HOME="$WORK/home" "$REPORT" "$WORK/bare.json" --repo my/demo | head -1)
check "default path: scratch/<repo>/review-<UTC>.md" $(echo "$STDOUT" | grep -Eq "^$WORK/home/.claude/scratch/my-demo/review-[0-9]{8}T[0-9]{6}Z\.md$" && [ -f "$STDOUT" ]; echo $?)

# --- unparseable input -------------------------------------------------------
echo 'this is not json at all {' > "$WORK/bad.txt"
"$REPORT" "$WORK/bad.txt" --repo demo --out "$WORK/bad.md" >/dev/null 2>"$WORK/bad.err"; RC=$?
check "unparseable: exit 1, no report written" $([ "$RC" -eq 1 ] && [ ! -e "$WORK/bad.md" ] && [ -s "$WORK/bad.err" ]; echo $?)
echo '{"summary":"no result key"}' > "$WORK/noresult.json"
"$REPORT" "$WORK/noresult.json" --repo demo --out "$WORK/nr.md" >/dev/null 2>&1; RC=$?
check "no actionable key: exit 1" $([ "$RC" -eq 1 ]; echo $?)
"$REPORT" "$WORK/missing.json" --repo demo --out "$WORK/m.md" >/dev/null 2>&1; RC=$?
check "missing file: exit 1" $([ "$RC" -eq 1 ]; echo $?)

echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
