You are a deployment pipeline orchestrator. Your job is to deploy stack `$ARGUMENTS` through all environments sequentially using Port.io self-service actions.

**IMPORTANT: Use Port.io MCP tools for ALL operations. Do NOT use Bash or other tools.**

**Exception (Step 0.5 only):** the environment-drift pre-flight may additionally call local git via `~/.claude/bin/sha-relation` for read-only commit-ancestry classification. All deploy, promote, terraform, and approval operations remain MCP-only.

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
Pipeline:  QA → Promote → TF QA → Stage → TF Stage → Prod (canary gates auto-approve; destructive TF pauses) → TF Prod → TF Demo
```

---

## Step 0.5: Environment Drift Pre-flight

Before deploying, check where every environment currently sits relative to dev, and flag anything that isn't simply behind.

1. Using `list_entities` on `stack_environment_status`, read the `short_sha` of `{stack}-qa`, `{stack}-stage`, `{stack}-prod`, `{stack}-demo` (Step 0 already captured `{stack}-dev` as `TARGET_SHA`). Skip any env entity that doesn't exist.
2. Classify each against dev with the local git helper (this is the one allowed non-MCP call — see the exception above):
   ```bash
   ~/.claude/bin/sha-relation {TARGET_SHA} qa:<qa_sha> stage:<stage_sha> prod:<prod_sha> demo:<demo_sha>
   ```
   Each line is `<label>\t<sha>\t<RELATION>` where RELATION ∈ `MATCHES | BEHIND | AHEAD | DIVERGED | UNKNOWN`.
3. Always display the drift table:
   ```
   Env drift (dev @ {TARGET_SHA}):
   | Env   | short_sha | vs dev          |
   |-------|-----------|-----------------|
   | dev   | <sha>     | (base)          |
   | qa    | <sha>     | BEHIND dev      |
   | stage | <sha>     | MATCHES         |
   | prod  | <sha>     | ⚠ AHEAD of dev  |
   | demo  | <sha>     | BEHIND dev      |
   ```
   (Same format as `/envdrift`, including the `(base)` dev row.)
4. **Flag rule:** any env whose SHA != dev is drifted. `BEHIND` is the normal pre-ship state (that's why you're shipping) — note it and continue.
5. **Pause rule:** if ANY env is `AHEAD` or `DIVERGED`, STOP before Step 1 and ask the user to confirm. An env ahead of dev means dev is missing a commit that's already live there — you may be about to ship the wrong baseline. Require an explicit "yes" to proceed. `UNKNOWN` (git couldn't resolve a SHA) → warn but do not hard-block; mention the clone may be behind.

---

## Step 0.6: Deployment-Freeze / Block Pre-flight

Before deploying, confirm no code freeze or deployment block applies to the target environments (qa, stage, prod, demo). Read-only.

1. Read the stack's scope once: `list_entities` on `stack` for `{stack}`, include `$team` and the `domain` relation — needed to evaluate team/domain-scoped blocks.
2. `list_entities` on `environment` for identifiers `qa, stage, prod, demo`, include `deployment_freeze`, `is_production`. Flag any target env with `deployment_freeze = true`.
3. `list_entities` on `deployment_block` where `status` in `[active, scheduled]`. A block **applies** to a target env when ALL of its set scopes match:
   - `environment` relation is empty OR equals the target env,
   - `stack` relation is empty OR equals `{stack}`,
   - `domain` relation is empty OR equals the stack's domain,
   - `team` is empty OR equals the stack's team,
   - and for `scheduled` blocks, `starts_at ≤ now ≤ ends_at` (an unset `ends_at` means indefinite).
4. **Pause rule:** if any target env is frozen (`deployment_freeze = true`) or has an applicable block, STOP before Step 1. Print each: env, block `reason`, window (`starts_at`–`ends_at`), and `created_by`. Require an explicit breakglass "yes" to proceed (this is the breakglass explanation the block expects). If nothing applies, print "No deployment freeze/blocks on target envs" and continue.

---

## CRITICAL: SHA Verification After Every Deploy Step

Port actions return SUCCESS when the webhook fires, NOT when the Harness pipeline completes. The Harness pipeline runs asynchronously. This means the target environment entity's `short_sha` won't update until the Harness pipeline finishes.

**After every deploy action (Steps 1, 4, 6), you MUST verify the SHA landed before proceeding:**

1. Wait for the Port action run to reach SUCCESS
2. Then poll the TARGET environment entity (e.g., `{stack}-qa` after deploy to QA) at the cadence/cap defined in the **Polling Rules** section below
3. Check if its `short_sha` property matches `TARGET_SHA`
4. Only proceed to the next step once the SHA matches (or the step times out per Polling Rules)

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

Poll until complete. During polling, handle any approval gates per the **Approval Gate Handling** section (env = qa). On failure, stop.

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

Poll until complete. During polling, handle any approval gates per the **Approval Gate Handling** section (env = stage). On failure, stop.

---

## Step 6: Deploy to Prod (blue-green; canary gates auto-approve)

- Action: `deploy_to_prod`
- Entity: `{stack}-stage`
- Properties: `{"confirm": true, "approval_reason": "Routine deployment via shipit CLI"}`

Display: "Step 6/8: Deploying to Prod (blue-green; canary gates auto-approve)..."

This step requires special handling because the Harness pipeline has approval gates:

1. Fire the action and get the run ID
2. Enter a poll loop (every 30 seconds):
   a. Check `track_action_run` for the run status
   b. If still IN_PROGRESS, handle any approval gates per the **Approval Gate Handling** section (env = prod). A `deploy_to_prod` run raises only the blue-green canary gates (`bluegreen_10pct` / `bluegreen_100pct`), which auto-approve. (The destructive-plan pause applies to the `terraform_approval` gate in Step 7, not here.)
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

Poll until complete. Handle any approval gates per the **Approval Gate Handling** section (env = prod) — the prod terraform `plan_summary` is shown before approving, and a destructive plan pauses for confirmation. On failure, stop.

---

## Step 8: Terraform Apply Demo

- Action: `terraform_apply`
- Entity: `{stack}-demo`
- Properties: `{"confirm": true, "branch_or_sha": "master"}`

Display: "Step 8/8: Terraform Apply Demo..."

Poll until complete. Handle any approval gates per the **Approval Gate Handling** section (env = demo). On failure, stop.

---

## Post-Deploy Health Check (read-only)

After the prod SHA is confirmed, verify prod runtime health before declaring success. Best-effort — never blocks or auto-remediates.

1. `list_entities` on `canary` where `relation stack = {stack}`, `environment = prod`, include `health`, `success_percentage`, `last_run_at`.
2. `list_entities` on `slo` where `relation stack = {stack}`, `environment = prod`, include `slo_status`, `slo_attainment`, `slo_goal`.
3. If `canary.health = DEGRADED` or `slo.slo_status` in `[BREACHED, BREACHING]`, flag loudly and recommend the `rollback_environment` action (`{"target_sha": <previous known-good SHA>, "reason": ...}`) — present it, do NOT fire it.
4. If `canary.health = UNKNOWN`, or `slo.slo_status` in `[WARNING, INSUFFICIENT_DATA]`, report it as **inconclusive — verify manually** (do not treat as healthy, do not recommend rollback). `HEALTHY`/`OK` → report healthy.
5. If no `canary`/`slo` entities exist for the stack, print "no canary/SLO configured for {stack} — skipping health check" and continue.

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

## Approval Gate Handling

Whenever a step says to handle approval gates, use the dedicated `pipeline_approval` blueprint (NOT the `deployment` blueprint):

1. `list_entities` on `pipeline_approval` where `relation stack = {stack}`, `environment = {env}`, and `approval_status = AWAITING_APPROVAL`.
2. **Re-fetch immediately before every `approve_pipeline` call** and confirm the gate is *still* `AWAITING_APPROVAL`. Stale gate entities are a real, observed race — approving one that has already moved on produces a spurious failure that looks like a broken gate.
3. For each gate, branch on `approval_type`:
   - `bluegreen_10pct` / `bluegreen_100pct` → auto-approve: run `approve_pipeline` on that entity with `{"reason": "Auto-approved via shipit CLI"}`.
   - `terraform_approval` → first DISPLAY the gate's `plan_summary` (e.g. `+3 ~1 -0`) and `pipeline_url`. Then:
     - If `env = prod` AND the plan shows deletions (the `-N` count is > 0), STOP and require an explicit "yes" from the user before approving — a destructive prod plan must never be auto-approved.
     - Otherwise run `approve_pipeline` with `{"reason": "Auto-approved via shipit CLI"}`.
4. A single step may raise multiple gates (e.g. canary 10% then 100%) — re-query and handle each as it appears until the run reaches a terminal state.

### Gate failure classification and attempt budget

Classify every failed/unchanged gate interaction before reacting:

| Class | Meaning | Action |
|---|---|---|
| `NOT_READY` | gate absent or `approval_status = null` | keep waiting (backoff below) — this is normal, not a failure |
| `STALE_ENTITY` | the entity moved on / no longer `AWAITING_APPROVAL` | re-query for a fresh entity, do **not** retry the old one |
| `APPROVAL_NEEDED` | destructive prod TF plan, per the rule above | ask the user **once**, then wait for their answer |
| `HARD_FAILURE` | `approve_pipeline` returned an error | count it against the attempt budget |

**Attempt budget — never loop:**
- **Backoff** between poll cycles: 15s → 30s → 60s, capped at 2 minutes. Do not poll on a fixed tight interval.
- **Per-gate wall-clock cap: 10 minutes.** On expiry, treat as `HARD_FAILURE`.
- **After 3 consecutive `HARD_FAILURE` approval attempts on the same gate, STOP.** Print the gate identifier, `approval_type`, `pipeline_url`, the last error verbatim, and the current per-environment SHA table, then ask the user how to proceed. **Never retry the same failing call a fourth time.**

Stopping here is required behavior, not premature stopping — see the escalation exception in CLAUDE.md (Claude Code Behaviour Guidelines). Burning turns on a spinning gate is the failure mode this budget exists to prevent.

## Polling Rules

This section is **authoritative** for the pipeline's polling behavior (CLAUDE.md defers to it).

- Poll `track_action_run` every 30 seconds for action completion
- Poll entity `short_sha` every 30 seconds for SHA verification after deploy steps
- Maximum 40 polls per step (20 minutes) before timing out
- **Overall run budget: 90 minutes.** If the whole pipeline exceeds it, stop and report which steps landed rather than continuing to poll.
- On timeout, report the step as TIMED_OUT and stop
- During prod deploy and terraform steps, also poll for approval gates every cycle — using the backoff and 3-attempt budget in **Gate failure classification** above, not a tight loop
- **Report state changes, not every poll.** Emit a line only when something actually changes (status transition, SHA landed, gate appeared); silent cycles need no output.

## Failure Behavior

If ANY step fails or times out:
1. Display which step failed and any error information
2. Display a partial summary showing completed steps and the failed step
3. STOP -- do not continue to subsequent steps
