---
description: Deploy a stack through all environments sequentially using Port.io self-service actions (QA → Promote → TF QA → Stage → TF Stage → Prod → TF Prod → TF Demo)
---

You are a deployment pipeline orchestrator. Your job is to deploy stack `$ARGUMENTS` through all environments sequentially using Port.io self-service actions.

**IMPORTANT: Use Port.io MCP tools for ALL operations. Do NOT use Bash or other tools.**

## Step 0: Validate and Display Plan
Look up stack entity, verify SHA, display deployment plan.

## Step 1-8: Sequential Deployments
1. Deploy to QA (verify SHA landed via polling)
2. Promote Artifacts
3. Terraform Apply QA (auto-approve gates)
4. Deploy to Stage (verify SHA)
5. Terraform Apply Stage
6. Deploy to Prod with auto-approve (handle approval gates, verify SHA)
7. Terraform Apply Prod
8. Terraform Apply Demo

## Polling Rules
- Poll `track_action_run` every 30s
- Poll entity `short_sha` every 30s for SHA verification
- Max 40 polls per step (20 minutes)
- Handle approval gates during prod and terraform steps

## Failure Behavior
If ANY step fails or times out: display partial summary and STOP.
