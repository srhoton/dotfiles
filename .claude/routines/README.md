# Routines

This folder contains **specs** for cloud-scheduled Claude Code agents (Routines). The actual schedules live at https://claude.ai/code/routines — files here are version-controlled source-of-truth that you copy-paste into the web UI.

## Workflow

1. Edit the routine markdown here.
2. Open https://claude.ai/code/routines.
3. Create or edit the matching routine: paste the prompt, set the trigger, configure secrets.
4. Save.

## Routines

| File | Trigger | Output |
|---|---|---|
| `01-stuck-deploy-sweep.md` | cron `0 * * * *` (hourly) | Slack DM (only when stuck deploys found) |
| `02-pr-on-open-review.md` | GitHub `pull_request.opened` + `ready_for_review` | Inline PR comments + Slack DM summary |
| `03-nightly-adr-drift.md` | cron `0 6 * * *` (6 AM daily) | Slack DM digest |

## Constraints

Cloud routines can only call **cloud-hosted MCPs**:

- ✓ claude.ai Port IO
- ✓ claude.ai Slack
- ✓ claude.ai Atlassian / Gmail / etc.
- ✗ Local stdio MCPs (harness-mcp-server, github via npx, aws via uvx, local discord plugin)

For anything that needs Harness, GitHub, or AWS data, use **WebFetch + REST API + a routine secret** (e.g., `GITHUB_TOKEN`, `HARNESS_API_TOKEN`).

## Secrets

Set per-routine in the Routines UI (NOT in the prompt). Each spec file lists its required secrets.

## Cost note

Each routine run consumes API tokens billed against your Pro/Max account. With all 3 active you'll see ~30-60 cloud runs/day. Monitor the first week.

## Testing

Each routine in the UI has a "Run now" button — use it after creating each routine to verify Slack output appears (or correctly stays silent when nothing's wrong).
