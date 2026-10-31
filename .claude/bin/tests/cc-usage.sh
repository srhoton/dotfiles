#!/bin/bash
#
# Tests for cc-usage. Every transcript is synthetic: a fixture tree is built under a temp
# directory and passed with --root, so no real session data is read. Prices used in the
# expectations are the list prices in cc-usage's PRICES table (opus input 4 / output 20 /
# cache read 0.20 per MTok; sonnet 2 / 10 / 0.20; haiku 1 / 5 / 0.10; cache writes 1.25x
# input at 5 minutes and 2x at 1 hour). Fixtures use 1,000,000-token amounts so the dollar
# figures are exact.
#
# Usage: bin/tests/cc-usage.sh        (exit 1 if any case fails)

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
CCU="$HERE/../cc-usage"
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

# ---- fixtures ------------------------------------------------------------------
python3 - "$WORK" <<'PY'
import json, os, sys

W = sys.argv[1]
M = 1_000_000


def put(root, rel, lines):
    path = os.path.join(W, root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        for ln in lines:
            fh.write(ln if isinstance(ln, str) else json.dumps(ln))
            fh.write("\n")


def resp(mid, ts="2026-10-20T12:00:00.000Z", model="claude-opus-5-5", uuid=None, block="text", **usage):
    """One transcript line of an assistant response (several lines may share mid)."""
    d = {"type": "assistant", "timestamp": ts, "uuid": uuid or f"u-{mid}-{block}-{ts}-{usage.get('output_tokens', 0)}",
         "message": {"id": mid, "model": model, "role": "assistant",
                     "content": [{"type": block}], "usage": usage}}
    if mid is None:
        del d["message"]["id"]
    return d


def meta(root, rel, agent_type):
    path = os.path.join(W, root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        json.dump({"agentType": agent_type, "isBuiltIn": False}, fh)


A = "-Users-tester-git-alpha"
B = "-Users-tester-git-beta"
C = "-Users-tester-notes"

# one response = three lines (thinking, text, tool_use) repeating the same usage: counts once
u = dict(input_tokens=100_000, output_tokens=10_000, cache_read_input_tokens=M)
put("dedupe", f"{A}/s1.jsonl", [resp("msg_a", block=b, **u) for b in ("thinking", "text", "tool_use")])

# no message.id: the line uuid is the key
put("uuid", f"{A}/s1.jsonl", [
    resp(None, uuid="same", input_tokens=M), resp(None, uuid="same", input_tokens=M),
    resp(None, uuid="other", input_tokens=M)])

# streaming rewrite: output_tokens grows (10 -> 50 in 10k units); a later, smaller line never wins
put("stream", f"{A}/s1.jsonl", [resp("msg_b", output_tokens=100_000), resp("msg_b", output_tokens=500_000)])
put("stream", f"{A}/s2.jsonl", [resp("msg_c", output_tokens=500_000), resp("msg_c", output_tokens=100_000)])

# cache writes: 3M tokens of which 1M are 1h and 2M 5m
cc = {"ephemeral_1h_input_tokens": M, "ephemeral_5m_input_tokens": 2 * M}
put("cache", f"{A}/s1.jsonl", [
    resp("w_opus", model="claude-opus-5-5", cache_creation_input_tokens=3 * M, cache_creation=cc),
    resp("w_son", model="claude-sonnet-5-5", cache_creation_input_tokens=3 * M, cache_creation=cc),
    # no breakdown: all of it is 5m
    resp("w_son2", model="claude-sonnet-5-5", cache_creation_input_tokens=M)])

# model tiers: 1M input, 1M output, 1M cache read each
tier_usage = dict(input_tokens=M, output_tokens=M, cache_read_input_tokens=M)
put("tiers", f"{A}/s1.jsonl", [
    resp("t1", model="claude-opus-5-5", **tier_usage), resp("t2", model="claude-sonnet-5-5", **tier_usage),
    resp("t3", model="claude-haiku-5-5", **tier_usage), resp("t4", model="claude-fable-5", **tier_usage)])

# agents: main, subagents (meta present / missing / malformed), workflow agents
one = dict(input_tokens=M)  # $4 on opus
put("agents", f"{A}/s1.jsonl", [resp("m1", **one)])
put("agents", f"{A}/s1/subagents/agent-a1.jsonl", [resp("a1", **one)])
meta("agents", f"{A}/s1/subagents/agent-a1.meta.json", "implementer")
put("agents", f"{A}/s1/subagents/agent-a2.jsonl", [resp("a2", **one)])  # no meta file
put("agents", f"{A}/s1/subagents/agent-a3.jsonl", [resp("a3", **one)])
put("agents", f"{A}/s1/subagents/agent-a3.meta.json", ["{not json"])
wf = f"{A}/s1/subagents/workflows/wf_1"
put("agents", f"{wf}/journal.jsonl", [
    {"type": "launched"}, "{garbage",
    {"type": "started", "agentId": "w1", "label": "review:functional"},
    {"type": "started", "agentId": "w2", "label": "review:quality"},
    {"type": "started", "agentId": "w3", "label": "verify:finding-3"},
    {"type": "result", "agentId": "w1", "result": {}}])
for i in (1, 2, 3, 4):  # w4 has no `started` event
    put("agents", f"{wf}/agent-w{i}.jsonl", [resp(f"wm{i}", **one)])
    meta("agents", f"{wf}/agent-w{i}.meta.json", "functional-reviewer")  # workflow type must not come from here
put("agents", f"{A}/s1/subagents/workflows/wf_2/agent-w5.jsonl", [resp("wm5", **one)])  # no journal at all

# windows: three $4 responses
put("windows", f"{A}/s1.jsonl", [
    resp("d1", ts="2026-10-10T12:00:00.000Z", **one), resp("d2", ts="2026-10-20T12:00:00.000Z", **one),
    resp("d3", ts="2026-10-28T12:00:00.000Z", **one)])

# by: two repos under -git-, one under the plain -Users-<user>- prefix, several runs
def ctx_resp(mid, ctx_input, cache_read):
    return resp(mid, input_tokens=ctx_input, cache_read_input_tokens=cache_read, output_tokens=1000)
put("by", f"{A}/s1.jsonl", [ctx_resp("x1", 100_000, 200_000), ctx_resp("x2", 1000, 1000)])
put("by", f"{A}/s2.jsonl", [ctx_resp(f"y{i}", 1000, 1000) for i in range(3)] + [ctx_resp("y9", 500_000, 0)])
put("by", f"{B}/s3.jsonl", [resp("z1", ts="2026-10-21T01:00:00.000Z", model="claude-sonnet-5-5", **one)])
put("by", f"{C}/s4.jsonl", [resp("n1", ts="2026-10-22T01:00:00.000Z", model="claude-haiku-5-5", **one)])
put("by", f"{A}/s2/subagents/agent-q.jsonl", [resp("q1", **one)])
meta("by", f"{A}/s2/subagents/agent-q.meta.json", "Explore")

# robustness: bad JSON, truncated tail, no usage, usage null, junk token values, a user line
put("robust", f"{A}/s1.jsonl", [
    '{not json "usage"', {"type": "user", "message": {"role": "user", "content": "hi"}},
    {"type": "assistant", "timestamp": "2026-10-20T12:00:00.000Z", "message": {"id": "nu", "model": "claude-opus-5-5"}},
    {"type": "assistant", "timestamp": "2026-10-20T12:00:00.000Z", "message": {"id": "nu2", "usage": None}},
    resp("junk", input_tokens="lots", output_tokens=None, cache_read_input_tokens=-5),
    resp("good", **one),
    '{"type":"assistant","message":{"usage":{"input_tokens":'])
put("robust", "-Users-tester-git-empty/sessions-index.json", ["{}"])

# synthetic responses are not API calls
put("synthetic", f"{A}/s1.jsonl", [resp("syn", model="<synthetic>", input_tokens=10 * M, output_tokens=10 * M), resp("real", **one)])
put("synthetic-only", f"{A}/s1.jsonl", [resp("syn", model="<synthetic>", input_tokens=10 * M)])
os.makedirs(os.path.join(W, "empty"), exist_ok=True)
PY

# ---- harness -------------------------------------------------------------------
ok()  { PASS=$((PASS + 1)); echo "ok    $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL  $1"; echo "      got: $2"; }

W_ARGS=(--since 2026-10-01 --until 2026-10-31)
cu() {  # ROOT-NAME args...  (stdout only; stderr dropped)
  local r="$1"; shift
  "$CCU" "${W_ARGS[@]}" --root "$WORK/$r" "$@" 2>/dev/null
}

# check CASE ROOT 'cu args' 'python body': d is the parsed --json output, g(name) one group.
# The body is a series of statements; any failed assert (or error) fails the case.
check() {
  local case="$1" root="$2" cargs="$3" body="$4" out
  # shellcheck disable=SC2086
  out=$(cu "$root" $cargs --json) || { bad "$case (cc-usage failed)" "$out"; return; }
  if printf '%s' "$out" | python3 -c "
import json, sys
d = json.load(sys.stdin)
def g(name):
    return next(x for x in d['groups'] if x['name'] == name)
def eq(a, b):
    assert abs(a - b) < 1e-6, (a, b)
$body
" 2>"$WORK/err"; then ok "$case"; else bad "$case" "$(tail -3 "$WORK/err") :: $(printf '%s' "$out" | head -c 400)"; fi
}

rc_is() {  # CASE WANT-RC command...
  local case="$1" want="$2" rc; shift 2
  "$@" >"$WORK/out" 2>&1; rc=$?
  if [ "$rc" = "$want" ]; then ok "$case"; else bad "$case (wanted rc=$want)" "rc=$rc $(head -c 300 "$WORK/out")"; fi
}

# ---- dedupe --------------------------------------------------------------------
check "three lines with one message.id count once" dedupe "--by kind" '
t = d["total"]
assert t["responses"] == 1 and t["runs"] == 1, t
eq(t["cost_usd"], 0.8)          # 0.1M*4 + 0.01M*20 + 1M*0.2
eq(t["input_usd"], 0.4); eq(t["output_usd"], 0.2); eq(t["cache_read_usd"], 0.2)'

check "no message.id: the line uuid dedupes, a different uuid is another response" uuid "--by kind" '
t = d["total"]
assert t["responses"] == 2, t
eq(t["cost_usd"], 8.0)'

check "streaming rewrite keeps the larger output_tokens (10 then 50)" stream "--by session" '
eq(g("s1")["output_usd"], 10.0); assert g("s1")["responses"] == 1
eq(g("s1")["cost_usd"], 10.0)'
check "  a later, smaller rewrite does not replace it (50 then 10)" stream "--by session" '
eq(g("s2")["output_usd"], 10.0); assert g("s2")["responses"] == 1'

# ---- pricing -------------------------------------------------------------------
check "cache writes split 1h (2x input) and 5m (1.25x input), opus" cache "--by model" '
o = g("claude-opus-5-5")
eq(o["cache_write_1h_usd"], 8.0)    # 1M * 4 * 2
eq(o["cache_write_5m_usd"], 10.0)   # 2M * 4 * 1.25
eq(o["cost_usd"], 18.0)'
check "  sonnet: 1h 4.00, 5m 5.00 plus 2.50 for a write with no breakdown" cache "--by model" '
s = g("claude-sonnet-5-5")
eq(s["cache_write_1h_usd"], 4.0)
eq(s["cache_write_5m_usd"], 7.5)    # 2M*2*1.25 + 1M*2*1.25
assert s["responses"] == 2'

check "model tiers: opus 24.20, sonnet 12.20, haiku 6.10 (cache read 0.10), fable priced as opus" tiers "--by model" '
eq(g("claude-opus-5-5")["cost_usd"], 24.2)
eq(g("claude-sonnet-5-5")["cost_usd"], 12.2)
eq(g("claude-haiku-5-5")["cost_usd"], 6.1)
eq(g("claude-haiku-5-5")["cache_read_usd"], 0.1)
eq(g("claude-sonnet-5-5")["cache_read_usd"], 0.2)
eq(g("claude-fable-5")["cost_usd"], 24.2)
eq(d["total"]["cost_usd"], 24.2 * 2 + 12.2 + 6.1)'

# ---- agent types ---------------------------------------------------------------
check "subagent type from meta, unknown without a usable meta file" agents "--by agent" '
eq(g("implementer")["cost_usd"], 4.0)
eq(g("unknown")["cost_usd"], 8.0)   # no meta file, and a malformed one
assert g("unknown")["runs"] == 2'
check "workflow type is workflow:<label prefix> from the journal" agents "--by agent" '
eq(g("workflow:review")["cost_usd"], 8.0)   # review:functional + review:quality
eq(g("workflow:verify")["cost_usd"], 4.0)'
check "  a workflow agent missing from the journal, or with no journal, is plain workflow" agents "--by agent" '
eq(g("workflow")["cost_usd"], 8.0)  # w4 and w5
assert g("workflow")["runs"] == 2
assert not any(x["name"] == "functional-reviewer" for x in d["groups"])'
check "main sessions are agent main" agents "--by agent" 'eq(g("main")["cost_usd"], 4.0)'
check "--by kind splits main, subagent, workflow" agents "--by kind" '
eq(g("main")["cost_usd"], 4.0); eq(g("subagent")["cost_usd"], 12.0); eq(g("workflow")["cost_usd"], 20.0)
eq(d["total"]["cost_usd"], 36.0); assert d["total"]["runs"] == 9, d["total"]
eq(sum(x["share_pct"] for x in d["groups"]), 100.0)'
check "journal.jsonl is not a transcript" agents "--by kind" 'assert d["total"]["runs"] == 9'

check "--agent implementer keeps only that agent" agents "--by agent --agent implementer" '
assert [x["name"] for x in d["groups"]] == ["implementer"]; eq(d["total"]["cost_usd"], 4.0)'
check "--agent workflow matches every workflow:* agent and plain workflow" agents "--by agent --agent workflow" '
assert sorted(x["name"] for x in d["groups"]) == ["workflow", "workflow:review", "workflow:verify"], d["groups"]
eq(d["total"]["cost_usd"], 20.0)'
check "--agent workflow:review is exact" agents "--by agent --agent workflow:review" '
assert [x["name"] for x in d["groups"]] == ["workflow:review"]; eq(d["total"]["cost_usd"], 8.0)'
check "--agent main" agents "--by kind --agent main" 'assert [x["name"] for x in d["groups"]] == ["main"]'

# ---- window --------------------------------------------------------------------
check "--since excludes older responses" windows "--since 2026-10-15 --by day" '
assert sorted(x["name"] for x in d["groups"]) == ["2026-10-20", "2026-10-28"], d["groups"]'
check "--until DATE includes that whole day" windows "--since 2026-10-15 --until 2026-10-28 --by day" '
eq(d["total"]["cost_usd"], 8.0)'
check "--until the day before excludes it" windows "--since 2026-10-15 --until 2026-10-27 --by day" '
eq(d["total"]["cost_usd"], 4.0)'
check "--until ISO datetime is exclusive" windows "--since 2026-10-15 --until 2026-10-28T12:00:00Z --by day" '
eq(d["total"]["cost_usd"], 4.0)'
check "--since ISO datetime is inclusive" windows "--since 2026-10-28T12:00:00Z --by day" 'eq(d["total"]["cost_usd"], 4.0)'
check "--since 36500d (relative days) reaches everything" windows "--since 36500d --until 2026-10-31 --by day" '
eq(d["total"]["cost_usd"], 12.0)'
check "--since 24h parses and the old fixtures fall outside it" windows "--since 24h --until 36500d --by day" 'eq(d["total"]["cost_usd"], 0.0)'
check "a window that excludes everything gives no groups and a zero total" windows "--since 1h --by kind" '
assert d["groups"] == [] and d["total"]["responses"] == 0'

# ---- --by ----------------------------------------------------------------------
# alpha: s1 has 2 responses (peak context 300k), s2 has 4 (peak 500k) + a subagent run (peak 1M).
check "--by repo strips -Users-<user>-git- and -Users-<user>-" by "--by repo" '
assert sorted(x["name"] for x in d["groups"]) == ["alpha", "beta", "notes"], d["groups"]
eq(g("beta")["cost_usd"], 2.0); eq(g("notes")["cost_usd"], 1.0)'
check "--by session names the session; a subagent belongs to its parent session" by "--by session" '
assert sorted(x["name"] for x in d["groups"]) == ["s1", "s2", "s3", "s4"], d["groups"]
assert g("s2")["runs"] == 2 and g("s2")["responses"] == 5, g("s2")'
check "runs, responses, median/max responses per run, peak context" by "--by kind --agent main --repo alpha" '
m = g("main")
assert m["runs"] == 2 and m["responses"] == 6, m
assert m["responses_per_run_median"] == 3 and m["responses_per_run_max"] == 4, m
assert m["peak_context_median"] == 400_000 and m["peak_context_max"] == 500_000, m'
check "peak context is input + cache_read + cache_creation of one response" by "--by agent --agent Explore" '
assert g("Explore")["peak_context_max"] == 1_000_000, g("Explore")'
check "--by day groups on the UTC date" by "--by day" '
assert sorted(x["name"] for x in d["groups"]) == ["2026-10-20", "2026-10-21", "2026-10-22"], d["groups"]'
check "--by model" by "--by model" '
assert sorted(x["name"] for x in d["groups"]) == ["claude-haiku-5-5", "claude-opus-5-5", "claude-sonnet-5-5"]
eq(g("claude-haiku-5-5")["cost_usd"], 1.0)'
check "--repo filters by substring before grouping" by "--by repo --repo et" '
assert [x["name"] for x in d["groups"]] == ["beta"], d["groups"]; eq(d["total"]["cost_usd"], 2.0)'
check "--top N keeps the dearest groups; TOTAL and omitted still cover the rest" by "--by session --top 1" '
assert len(d["groups"]) == 1 and d["omitted"]["groups"] == 3, d
eq(d["groups"][0]["cost_usd"] + d["omitted"]["cost_usd"], d["total"]["cost_usd"])'
check "groups are sorted by cost, dearest first" by "--by session --top 0" '
costs = [x["cost_usd"] for x in d["groups"]]
assert costs == sorted(costs, reverse=True) and len(costs) == 4, costs'

# ---- text vs --json ------------------------------------------------------------
text=$(cu by --by repo)
json=$(cu by --by repo --json)
if printf '%s' "$json" | python3 -c '
import json, re, sys
d, text = json.load(sys.stdin), sys.argv[1]
t = d["total"]
line = next(l for l in text.splitlines() if l.startswith("TOTAL"))
cells = line.split()
assert cells[1] == "${:,.2f}".format(t["cost_usd"]), (cells, t)
assert cells[2] == "100.0%" and cells[3] == str(t["runs"]) and cells[4] == str(t["responses"]), (cells, t)
for g in d["groups"]:
    row = next(l for l in text.splitlines() if l.split() and l.split()[0] == g["name"])
    assert row.split()[1] == "${:,.2f}".format(g["cost_usd"]), (row, g)
' "$text"; then ok "--json parses and its totals and groups match the text table"; else bad "text vs json" "$text"; fi
if printf '%s\n' "$text" | grep -Eq '^REPO +COST +SHARE +RUNS +RESP +RESP/RUN med/max +PEAK-CTX med/max +CACHE-RD +WRITE-1H +WRITE-5M +OUTPUT$'; then ok "text mode prints the aligned header"; else bad "text header" "$text"; fi
out=$(cu by --by repo --top 1)
if printf '%s\n' "$out" | grep -q '^\.\.\. 2 more group(s)'; then ok "text mode says how many groups --top left out"; else bad "omitted note" "$out"; fi

# ---- robustness ----------------------------------------------------------------
check "bad JSON, no usage, null usage, junk token values and a user line do not crash or count" robust "--by kind" '
t = d["total"]
assert t["responses"] == 2, t       # "junk" (all zero) and "good"
eq(t["cost_usd"], 4.0)'
err=$("$CCU" "${W_ARGS[@]}" --root "$WORK/robust" 2>&1 >/dev/null)
if printf '%s' "$err" | grep -q 'skipped 2 line(s) that were not valid JSON'; then ok "  skipped lines are reported on stderr"; else bad "skipped-lines note" "$err"; fi
rc_is "a missing meta file does not crash" 0 "$CCU" "${W_ARGS[@]}" --root "$WORK/agents"
check "<synthetic> responses cost nothing and are not counted" synthetic "--by model" '
assert [x["name"] for x in d["groups"]] == ["claude-opus-5-5"], d["groups"]
eq(d["total"]["cost_usd"], 4.0); assert d["total"]["responses"] == 1'
check "a transcript of only <synthetic> responses totals 0" synthetic-only "--by model" '
assert d["groups"] == [] and d["total"]["cost_usd"] == 0 and d["total"]["runs"] == 0'
check "an empty root totals 0" empty "--by kind" 'assert d["groups"] == [] and d["total"]["cost_usd"] == 0 and d["total"]["share_pct"] == 0'
out=$(cu empty)
if printf '%s\n' "$out" | grep -Eq '^TOTAL +\$0\.00'; then ok "  and the text table still ends in a TOTAL line"; else bad "empty text" "$out"; fi

# ---- usage ---------------------------------------------------------------------
rc_is "bad --since is a usage error (exit 2)" 2 "$CCU" --since yesterday --root "$WORK/empty"
rc_is "bad --until is a usage error (exit 2)" 2 "$CCU" --until 2026-13-45 --root "$WORK/empty"
rc_is "unknown --by is a usage error (exit 2)" 2 "$CCU" --by nope --root "$WORK/empty"
rc_is "non-numeric --top is a usage error (exit 2)" 2 "$CCU" --top x --root "$WORK/empty"
rc_is "negative --top is a usage error (exit 2)" 2 "$CCU" --top -1 --root "$WORK/empty"
rc_is "a missing root is a usage error (exit 2)" 2 "$CCU" --root "$WORK/does-not-exist"
rc_is "an unknown option is a usage error (exit 2)" 2 "$CCU" --bogus
rc_is "--help exits 0" 0 "$CCU" --help
if grep -q 'Usage: cc-usage' "$WORK/out" && grep -q 'counted once per API response' "$WORK/out"; then ok "  and prints the docstring"; else bad "--help text" "$(head -c 200 "$WORK/out")"; fi
rc_is "defaults (7d window, by kind) run" 0 "$CCU" --root "$WORK/empty"

echo
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" = 0 ]
