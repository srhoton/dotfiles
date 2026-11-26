#!/bin/bash
#
# guard-agent-model.sh - PreToolUse(Agent|Task) hook for Claude Code
#
# Keeps the model split fixed: the code-writing agents and the code-quality
# reviewer run on Sonnet, and the other reviewers run on Opus. Each agent pins
# its model in frontmatter, but the Agent tool's `model` parameter overrides
# frontmatter, so this hook blocks a call that passes a different model for one
# of those agents.
#
# Calls with no `model`, and agent types not listed here, pass through.
# agent() calls inside a Workflow don't reach hooks; workflows/review-fanout.js
# sets its model itself.
#
# Exit 2 = block, stderr is fed back to Claude. Exit 0 = allow.
#

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

printf '%s' "$INPUT" | python3 -c "
import json, sys

SONNET = {
    'implementer', 'code-quality-reviewer',
}
OPUS = {
    'functional-reviewer', 'adr-compliance-reviewer',
    'performance-reviewer', 'data-side-effects-reviewer', 'finding-verifier',
}

try:
    ti = json.load(sys.stdin).get('tool_input') or {}
except Exception:
    sys.exit(0)
agent = str(ti.get('subagent_type') or '')
model = str(ti.get('model') or '').strip().lower()
if not agent or not model:
    sys.exit(0)

want = 'sonnet' if agent in SONNET else 'opus' if agent in OPUS else None
# Accept an alias ('sonnet') or a full id ('claude-sonnet-5-5').
if want is None or want in model:
    sys.exit(0)

if want == 'opus':
    role = 'is a reviewer and is pinned to Opus'
elif agent == 'implementer':
    role = 'writes code and is pinned to Sonnet'
else:
    role = 'is a cost-tuned reviewer and is pinned to Sonnet'
print(
    f\"BLOCKED: {agent} {role}; this call passed model '{model}'.\n\"
    'Re-dispatch without the model parameter so the agent frontmatter decides.',
    file=sys.stderr,
)
sys.exit(2)
"
