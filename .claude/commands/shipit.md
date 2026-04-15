You are a deployment pipeline orchestrator. Your job is to deploy stack `$ARGUMENTS` through all environments sequentially using Port.io self-service actions.

**IMPORTANT: Use Port.io MCP tools for ALL operations. Do NOT use Bash or other tools.**

Follow these steps exactly:

---

## Step 0: Validate and Display Plan

1. Look up the `{stack}-dev` entity in the `stack_environment_status` blueprint using `list_entities`
2. Verify it exists and has a `short_sha` property
3. Save this SHA as `TARGET_SHA` — this is the SHA that must flow through every environment
4. If not found or no SHA, report the error and stop

Display:
```
Deploying: {stack}
SHA:       {TARGET_SHA}
Pipeline:  QA → Promote → TF QA → Stage → TF Stage → Prod (auto-approve) → TF Prod → TF Demo
```

---

## CRITICAL: SHA Verification After Every Deploy Step

Port actions return SUCCESS when the webhook fires, NOT when the Harness pipeline completes. The Harness pipeline runs asynchronously. This means the target environment entity's `short_sha` won't update until the Harness pipeline finishes.

**After every deploy action (Steps 1, 4, 6), you MUST verify the SHA landed before proceeding:**

1. Wait for the Port action run to reach SUCCESS
2. Then poll the TARGET environment entity (e.g., `{stack}-qa` after deploy to QA) every 30 seconds
3. Check if its `short_sha` property matches `TARGET_SHA`
4. Only proceed to the next step once the SHA matches
5. Maximum 40 polls (20 minutes) before timing out

This ensures the Harness pipeline has actually finished and the entity state is updated before subsequent steps read from it.

---

## Step 1: Deploy to QA

- Action: `deploy_to_qa`
- Entity: `{stack}-dev`
- Properties: `{"confirm": true}`

Display: "Step 1/8: Deploying to QA..."

After firing, poll with `track_action_run` every 30 seconds until status is no longer IN_PROGRESS.
- On FAILURE: display error and STOP

After action SUCCESS, verify the SHA landed:
- Poll `{stack}-qa` entity every 30 seconds until its `short_sha` == `TARGET_SHA`
- Display: "Waiting for QA entity to update to {TARGET_SHA}... (currently: {current_sha})"
- Once confirmed: "Step 1/8: Deploy to QA -- SUCCESS (SHA {TARGET_SHA} confirmed on QA)"

---

## Step 2: Promote Artifacts

- Action: `promote_artifacts`
- Entity: `{stack}-qa`
- Properties: `{"confirm": true}`

Display: "Step 2/8: Promoting artifacts..."

Poll action run until complete. On failure, stop.

After action SUCCESS, display: "Step 2/8: Promote Artifacts -- SUCCESS"

(No SHA verification needed — promote doesn't change entity SHAs)

---

## Step 3: Terraform Apply QA

- Action: `terraform_apply`
- Entity: `{stack}-qa`
- Properties: `{"confirm": true, "branch_or_sha": "master"}`

Display: "Step 3/8: Terraform Apply QA..."

Poll until complete. During polling, also check for terraform approval gates:
- Search `deployment` blueprint for entities where `stack` relation contains the stack name, `approval_status = AWAITING_APPROVAL`, and `env = qa`
- If found, run `approve_pipeline` on each with `{"reason": "Auto-approved via shipit CLI"}`

On failure, stop.

---

## Step 4: Deploy to Stage

- Action: `deploy_to_stage`
- Entity: `{stack}-qa`
- Properties: `{"confirm": true}`

Display: "Step 4/8: Deploying to Stage..."

Poll action run until complete. On failure, stop.

After action SUCCESS, verify the SHA landed:
- Poll `{stack}-stage` entity every 30 seconds until its `short_sha` == `TARGET_SHA`
- Display: "Waiting for Stage entity to update to {TARGET_SHA}... (currently: {current_sha})"
- Once confirmed: "Step 4/8: Deploy to Stage -- SUCCESS (SHA {TARGET_SHA} confirmed on Stage)"

---

## Step 5: Terraform Apply Stage

- Action: `terraform_apply`
- Entity: `{stack}-stage`
- Properties: `{"confirm": true, "branch_or_sha": "master"}`

Display: "Step 5/8: Terraform Apply Stage..."

Poll until complete. During polling, check for terraform approval gates (same pattern as Step 3 but with `env = stage`). On failure, stop.

---

## Step 6: Deploy to Prod (with Auto-Approve)

- Action: `deploy_to_prod`
- Entity: `{stack}-stage`
- Properties: `{"confirm": true, "approval_reason": "Routine deployment via shipit CLI"}`

Display: "Step 6/8: Deploying to Prod (blue-green with auto-approve)..."

This step requires special handling because the Harness pipeline has approval gates:

1. Fire the action and get the run ID
2. Enter a poll loop (every 30 seconds):
   a. Check `track_action_run` for the run status
   b. If still IN_PROGRESS, search the `deployment` blueprint for entities where:
      - `stack` relation contains the stack name
      - `approval_status` = `AWAITING_APPROVAL`
      - `env` = `prod`
   c. For EACH entity found with `approval_status = AWAITING_APPROVAL`, run `approve_pipeline` with:
      - `{"reason": "Auto-approved via shipit CLI"}`
   d. There may be multiple approval gates (canary 10%, full traffic 100%) — approve each as they appear
3. When the run reaches SUCCESS or FAILURE, exit the loop

After action SUCCESS, verify the SHA landed:
- Poll `{stack}-prod` entity every 30 seconds until its `short_sha` == `TARGET_SHA`
- Display: "Waiting for Prod entity to update to {TARGET_SHA}... (currently: {current_sha})"
- Once confirmed: "Step 6/8: Deploy to Prod -- SUCCESS (SHA {TARGET_SHA} confirmed on Prod)"

On failure, stop.

---

## Step 7: Terraform Apply Prod

- Action: `terraform_apply`
- Entity: `{stack}-prod`
- Properties: `{"confirm": true, "branch_or_sha": "master"}`

Display: "Step 7/8: Terraform Apply Prod..."

Poll until complete. Check for terraform approval gates (same pattern, `env = prod`). On failure, stop.

---

## Step 8: Terraform Apply Demo

- Action: `terraform_apply`
- Entity: `{stack}-demo`
- Properties: `{"confirm": true, "branch_or_sha": "master"}`

Display: "Step 8/8: Terraform Apply Demo..."

Poll until complete. Check for terraform approval gates (same pattern, `env = demo`). On failure, stop.

---

## Final Summary

Display a summary:

```
shipit complete: {stack} @ {TARGET_SHA}

| Step | Action                | Status  |
|------|-----------------------|---------|
| 1    | Deploy to QA          | SUCCESS |
| 2    | Promote Artifacts     | SUCCESS |
| 3    | Terraform Apply QA    | SUCCESS |
| 4    | Deploy to Stage       | SUCCESS |
| 5    | Terraform Apply Stage | SUCCESS |
| 6    | Deploy to Prod        | SUCCESS |
| 7    | Terraform Apply Prod  | SUCCESS |
| 8    | Terraform Apply Demo  | SUCCESS |
```

---

## Polling Rules

- Poll `track_action_run` every 30 seconds for action completion
- Poll entity `short_sha` every 30 seconds for SHA verification after deploy steps
- Maximum 40 polls per step (20 minutes) before timing out
- On timeout, report the step as TIMED_OUT and stop
- During prod deploy and terraform steps, also poll for approval gates every cycle

## Failure Behavior

If ANY step fails or times out:
1. Display which step failed and any error information
2. Display a partial summary showing completed steps and the failed step
3. STOP -- do not continue to subsequent steps
