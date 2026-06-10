# Routine 1 — Stuck / Failed Deploy Sweep

**Trigger:** cron `0 * * * *` (every hour, top of hour)

**Cloud MCPs used:**
- `claude.ai Port IO` — primary data source
- `claude.ai Slack` — output

**Secrets:**
- `HARNESS_API_TOKEN` — optional, enables Harness cross-check on stuck IN_PROGRESS entities

## Detection rules

All from Port.io's `deployment` blueprint:

| Detection | Port.io query |
|---|---|
| Missed approve gate | `approval_status = AWAITING_APPROVAL` AND `timestamp` older than 30 min |
| Aborted pipeline | `status = FAILED` AND `timestamp` in last 1 hour AND `error` not empty |
| Canary needs human | `approval_status = AWAITING_APPROVAL` AND `approval_type` in (`bluegreen_10pct`, `bluegreen_100pct`) |
| Silently stuck | `status = IN_PROGRESS` AND `timestamp` older than 30 min |

## Output (Slack DM)

```
🚨 Stuck/failed deploys (3)

Missed approve:
- mig-start-mg-fun → prod (bluegreen_10pct, 47 min) [link]

Aborted:
- ath-rebac-svc → stage (Test failed, 22 min ago) [link]

Stuck IN_PROGRESS:
- mig-wor-mg-fun → qa (52 min, Harness shows: paused) [link]
```

If zero hits, **silent** — no Slack message.

## Routine prompt (paste this into claude.ai/code/routines)

```
You are a deploy-health sweeper. Every hour, scan Port.io for stuck or failed deployments and notify me on Slack only if there's something to report.

Steps:
1. Use mcp__claude_ai_Port_IO__list_entities to query the `deployment` blueprint. Filter for entities created in the last 4 hours (use `timestamp` >= now - 4h).

2. Bucket the results into four categories:

   A. MISSED_APPROVE: `approval_status = AWAITING_APPROVAL` AND timestamp > 30 min old
   B. ABORTED: `status = FAILED` AND timestamp in last 60 min AND error field non-empty
   C. CANARY_WAITING: `approval_status = AWAITING_APPROVAL` AND `approval_type` in [bluegreen_10pct, bluegreen_100pct]
   D. SILENTLY_STUCK: `status = IN_PROGRESS` AND timestamp > 30 min old

3. For each SILENTLY_STUCK hit, if HARNESS_API_TOKEN is set, WebFetch the pipeline_url and check the actual Harness execution state. Include the Harness verdict ("paused", "running", "failed", etc.) in the report.

4. If all four buckets are empty, EXIT SILENTLY — do not post to Slack.

5. Otherwise, post a Slack DM to the user with a compact summary formatted exactly like:

   🚨 Stuck/failed deploys (N)

   Missed approve:
   - <stack> → <env> (<approval_type>, <age>) [<pipeline_url>]

   Aborted:
   - <stack> → <env> (<error>, <age> ago) [<pipeline_url>]

   Canary waiting:
   - <stack> → <env> (<approval_type>, <age>) [<pipeline_url>]

   Stuck IN_PROGRESS:
   - <stack> → <env> (<age>, Harness shows: <verdict>) [<pipeline_url>]

   Only include buckets that have hits. Use pipeline_url as the [link] target.

6. Mark this run done. Do not post duplicate alerts within the same hour for the same deployment entity.

Constraints:
- Concise output. No narrative. Only the bullet list.
- Failure recovery: if Port.io MCP times out, exit cleanly and try next hour.
- Cap each bucket at 10 entries; if more, suffix with "(+N more)".
```
