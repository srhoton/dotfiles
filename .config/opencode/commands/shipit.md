---
description: "Deploy a stack through qa, stage, or (default) all environments using Port.io self-service actions."
---
You are a deployment pipeline orchestrator. Your job is to deploy a stack sequentially through the environments up to a target environment (qa, stage, or prod by default) using Port.io self-service actions. The arguments are `$ARGUMENTS`.

## Step −1: Parse Arguments

Parse `$ARGUMENTS` before calling anything:

- **`STACK`**: the first word. Every `{stack}` below means `STACK`.
- **`TARGET_ENV`**: `qa`, `stage` or `prod`, given as the second word or as `--to <env>`. It defaults to **`prod`**, so `/shipit <stack>` behaves exactly as before.
- **`DRY_RUN`**: true when `--dry-run` is present.
- **On bad input, stop** without making any Port call and print `Usage: /shipit <stack> [qa|stage|prod] [--dry-run]`. Bad input means:
  - no stack;
  - a target other than qa, stage or prod (`dev` and `demo` can't be targets; demo ships only as part of a prod run);
  - more than one target;
  - an unknown flag.

**Steps per target.** This table decides which steps run. Every step section below starts with a guard that refers to it.

| `TARGET_ENV` | Steps in this run | N |
|---|---|---|
| `qa` | 1 Deploy to QA, 3 Terraform Apply QA | 2 |
| `stage` | 1 Deploy to QA, 2 Promote Artifacts, 3 Terraform Apply QA, 4 Deploy to Stage, 5 Terraform Apply Stage | 5 |
| `prod` | 1–8 | 8 |

- **Envs in scope:** `qa` for qa; `qa, stage` for stage; `qa, stage, prod, demo` for prod.
- **Why promote is skipped for qa:** Promote Artifacts only makes the SHA available to stage and prod.
- **Step numbering:** the `Display:` lines below are written for a full prod run as `Step k/8`. In a shorter run, show the step's position in this run's plan instead, e.g. `Step 2/2: Terraform Apply QA...` for a qa run.

**Dry run.** With `DRY_RUN`, run Step 0, Step 0.5 and Step 0.6 (all read-only), then print the plan and stop: the target, each step that would run (action, entity, inputs), and "Dry run: nothing was triggered". Never call `trigger_run`, `run_action` or `approve_pipeline` in a dry run.

**IMPORTANT: Use Port.io MCP tools for ALL operations. Do NOT use Bash or other tools.**

**Exception (Step 0.5 only):** the environment-drift pre-flight may additionally call local git via `~/.claude/bin/sha-relation` for read-only commit-ancestry classification. All deploy, promote, terraform, and approval operations remain MCP-only.

## Port MCP tools to use

- **Fire an action** with `trigger_run`: `type: "ACTION"`, `identifier` = the step's action (e.g. `deploy_to_qa`), `entityIdentifier` = the step's entity, `inputs` = the step's properties. Keep the returned run ID.
- **Poll a run** with `get_run` (`runId`). It returns `status`, `statusLabel`, `summary`, `response` and approval info.
- `run_action` and `track_action_run` are Port's legacy forms of these two tools. Use them only if `trigger_run`/`get_run` are missing from the session, and say so in the output.
- **Read environment SHAs in one call:** `list_entities` on `stack_environment_status` with `identifiers` set to every env you need (e.g. `[{stack}-dev, {stack}-qa, {stack}-stage, {stack}-prod, {stack}-demo]`) and `include: ["short_sha"]`. Don't read the environments one call each.

Follow these steps exactly:

---

## Step 0: Validate and Display Plan

1. Read all five environment entities in **one** `list_entities` call on `stack_environment_status`: `identifiers: [{stack}-dev, {stack}-qa, {stack}-stage, {stack}-prod, {stack}-demo]`, `include: ["short_sha"]`. Keep the result; Step 0.5 uses it.
2. Verify `{stack}-dev` exists and has a `short_sha` property
3. Save this SHA as `TARGET_SHA` — this is the SHA that must flow through every environment
4. If not found or no SHA, report the error and stop

Display:
```
Deploying: {stack}
SHA:       {TARGET_SHA}
Target:    {TARGET_ENV}
Pipeline:  <only this run's steps>
```
The `Pipeline:` line for each target:

| Target | Pipeline |
|---|---|
| qa | `QA → TF QA` |
| stage | `QA → Promote → TF QA → Stage → TF Stage` |
| prod | `QA → Promote → TF QA → Stage → TF Stage → Prod (canary gates auto-approve; destructive TF pauses) → TF Prod → TF Demo` |

---

## Step 0.5: Environment Drift Pre-flight

Before deploying, check where every environment currently sits relative to dev, and flag anything that isn't simply behind.

1. Take the `short_sha` of `{stack}-qa`, `{stack}-stage`, `{stack}-prod` and `{stack}-demo` from the Step 0 read (no second call; `{stack}-dev` is `TARGET_SHA`). Skip any env entity that doesn't exist.
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
5. **Pause rule:** if ANY env **in scope for this target** (see Step −1) is `AHEAD` or `DIVERGED`, STOP before Step 1 and ask the user to confirm. If an env outside the scope is AHEAD or DIVERGED (e.g. prod on a qa run), print a warning and continue, because this run doesn't touch it. An env ahead of dev means dev is missing a commit that's already live there — you may be about to ship the wrong baseline. Require an explicit "yes" to proceed. `UNKNOWN` (git couldn't resolve a SHA) → warn but do not hard-block; mention the clone may be behind.

---

## Step 0.6: Deployment-Freeze / Block Pre-flight

Before deploying, confirm no code freeze or deployment block applies to the environments **in scope for this target** (Step −1: `qa`; `qa, stage`; or `qa, stage, prod, demo`). Below, "target envs" means those environments. Read-only.

1. Read the stack's scope once: `list_entities` on `stack` for `{stack}`, include `$team` and the `domain` relation — needed to evaluate team/domain-scoped blocks.
2. `list_entities` on `environment` for the target envs' identifiers, include `deployment_freeze`, `is_production`. Flag any target env with `deployment_freeze = true`.
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

*Runs for every target.*

- Action: `deploy_to_qa`
- Entity: `{stack}-dev`
- Properties: `{"confirm": true}`

Display: "Step 1/8: Deploying to QA..."

After firing with `trigger_run`, poll with `get_run` every 30 seconds until status is no longer IN_PROGRESS.
- On FAILURE: display error and STOP

After action SUCCESS, verify the SHA landed:
- Poll `{stack}-qa` entity every 30 seconds until its `short_sha` == `TARGET_SHA`
- Display: "Waiting for QA entity to update to {TARGET_SHA}... (currently: {current_sha})"
- Once confirmed: "Step 1/8: Deploy to QA -- SUCCESS (SHA {TARGET_SHA} confirmed on QA)"

---

## Step 2: Promote Artifacts

*Runs only when `TARGET_ENV` is `stage` or `prod`. Skip it for `qa`.*

- Action: `promote_artifacts`
- Entity: `{stack}-qa`
- Properties: `{"confirm": true}`

Display: "Step 2/8: Promoting artifacts..."

Poll action run until complete. On failure, stop.

After action SUCCESS, display: "Step 2/8: Promote Artifacts -- SUCCESS"

(No SHA verification needed — promote doesn't change entity SHAs)

---

## Step 3: Terraform Apply QA

*Runs for every target.*

- Action: `terraform_apply`
- Entity: `{stack}-qa`
- Properties: `{"confirm": true, "branch_or_sha": "master"}`

Display: "Step 3/8: Terraform Apply QA..."

Poll until complete. During polling, handle any approval gates per the **Approval Gate Handling** section (env = qa). On failure, stop.

---

## Step 4: Deploy to Stage

*Runs only when `TARGET_ENV` is `stage` or `prod`. A qa run ends after Step 3; go to the Post-Deploy Health Check.*

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

*Runs only when `TARGET_ENV` is `stage` or `prod`.*

- Action: `terraform_apply`
- Entity: `{stack}-stage`
- Properties: `{"confirm": true, "branch_or_sha": "master"}`

Display: "Step 5/8: Terraform Apply Stage..."

Poll until complete. During polling, handle any approval gates per the **Approval Gate Handling** section (env = stage). On failure, stop.

---

## Step 6: Deploy to Prod (blue-green; canary gates auto-approve)

*Runs only when `TARGET_ENV` is `prod`. A stage run ends after Step 5; go to the Post-Deploy Health Check.*

- Action: `deploy_to_prod`
- Entity: `{stack}-stage`
- Properties: `{"confirm": true, "approval_reason": "Routine deployment via shipit CLI"}`

Display: "Step 6/8: Deploying to Prod (blue-green; canary gates auto-approve)..."

This step requires special handling because the Harness pipeline has approval gates:

1. Fire the action with `trigger_run` and get the run ID
2. Enter a poll loop (every 30 seconds):
   a. Check `get_run` for the run status
   b. If still IN_PROGRESS, handle any approval gates per the **Approval Gate Handling** section (env = prod). A `deploy_to_prod` run raises only the blue-green canary gates (`bluegreen_10pct` / `bluegreen_100pct`), which auto-approve. (The destructive-plan pause applies to the `terraform_approval` gate in Step 7, not here.)
3. When the run reaches SUCCESS or FAILURE, exit the loop

After action SUCCESS, verify the SHA landed:
- Poll `{stack}-prod` entity every 30 seconds until its `short_sha` == `TARGET_SHA`
- Display: "Waiting for Prod entity to update to {TARGET_SHA}... (currently: {current_sha})"
- Once confirmed: "Step 6/8: Deploy to Prod -- SUCCESS (SHA {TARGET_SHA} confirmed on Prod)"

On failure, stop.

---

## Step 7: Terraform Apply Prod

*Runs only when `TARGET_ENV` is `prod`.*

- Action: `terraform_apply`
- Entity: `{stack}-prod`
- Properties: `{"confirm": true, "branch_or_sha": "master"}`

Display: "Step 7/8: Terraform Apply Prod..."

Poll until complete. Handle any approval gates per the **Approval Gate Handling** section (env = prod) — the prod terraform `plan_summary` is shown before approving, and a destructive plan pauses for confirmation. On failure, stop.

---

## Step 8: Terraform Apply Demo

*Runs only when `TARGET_ENV` is `prod`.*

- Action: `terraform_apply`
- Entity: `{stack}-demo`
- Properties: `{"confirm": true, "branch_or_sha": "master"}`

Display: "Step 8/8: Terraform Apply Demo..."

Poll until complete. Handle any approval gates per the **Approval Gate Handling** section (env = demo). On failure, stop.

---

## Post-Deploy Health Check (read-only)

After the last deploy step's SHA is confirmed, verify the runtime health of **`TARGET_ENV`** (the run's final environment) before declaring success. Best-effort — never blocks or auto-remediates.

1. `list_entities` on `canary` where `relation stack = {stack}`, `environment = {TARGET_ENV}`, include `health`, `success_percentage`, `last_run_at`.
2. `list_entities` on `slo` where `relation stack = {stack}`, `environment = {TARGET_ENV}`, include `slo_status`, `slo_attainment`, `slo_goal`.
3. If `canary.health = DEGRADED` or `slo.slo_status` in `[BREACHED, BREACHING]`, flag loudly.
   - On a **prod** run, also recommend the `rollback_environment` action (`{"target_sha": <previous known-good SHA>, "reason": ...}`). Present it; do NOT fire it.
   - On a **qa or stage** run, recommend investigating before promoting further. Don't suggest a rollback.
4. If `canary.health = UNKNOWN`, or `slo.slo_status` in `[WARNING, INSUFFICIENT_DATA]`, report it as **inconclusive — verify manually** (do not treat as healthy, do not recommend rollback). `HEALTHY`/`OK` → report healthy.
5. If no `canary`/`slo` entities exist for the stack, print "no canary/SLO configured for {stack} — skipping health check" and continue.

---

## Final Summary

Display a summary that lists **only the steps this run executed**. The example below is a full prod run. For a shorter run, end with a line naming the environments it left alone, so a partial run is never mistaken for a full one:

| Target | Last line |
|---|---|
| qa | `Not shipped this run: stage, prod, demo` |
| stage | `Not shipped this run: prod, demo` |

```
shipit complete: {stack} @ {TARGET_SHA} → {TARGET_ENV}

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
5. **Cross-check with `list_runs`** (`types: ["ACTION"]`, `waitingForApproval: true`) on each gate poll.
   - **This step's run is listed** (status `WAITING_FOR_APPROVAL`): that's a **Port-level** action approval, not a Harness `pipeline_approval` gate. shipit does not approve those. Print the run ID and its approval info from `get_run`, then ask the user.
   - **A gate is waiting in step 1 but this run isn't listed:** that's normal. Harness gates surface only as `pipeline_approval` entities.

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

Stopping here is required behavior, not premature stopping — see the escalation exception in AGENTS.md (Claude Code Behaviour Guidelines). Burning turns on a spinning gate is the failure mode this budget exists to prevent.

## Polling Rules

This section is **authoritative** for the pipeline's polling behavior (AGENTS.md defers to it).

- Poll `get_run` every 30 seconds for action completion
- Poll entity `short_sha` every 30 seconds for SHA verification after deploy steps
- **Cache flicker:** a run's status can oscillate between IN_PROGRESS and SUCCESS. Read the same terminal state on 2-3 consecutive polls before treating it as final.
- **Stale entity:** before firing a deploy or terraform action, confirm the target entity's `short_sha` matches the expected commit on origin. If it doesn't, wait 30s and re-fetch; never fire against a stale entity.
- Maximum 40 polls per step (20 minutes) before timing out
- **Overall run budget: 90 minutes.** If the whole pipeline exceeds it, stop and report which steps landed rather than continuing to poll.
- On timeout, report the step as TIMED_OUT and stop
- During prod deploy and terraform steps, also poll for approval gates every cycle — using the backoff and 3-attempt budget in **Gate failure classification** above, not a tight loop
- **Report state changes, not every poll.** Emit a line only when something actually changes (status transition, SHA landed, gate appeared); silent cycles need no output.

## Failure Behavior

If ANY step fails or times out:
1. **Diagnose before reporting** (read-only; never re-fire or approve anything here):
   - `get_run` on the step's run ID. Report its `status`, `statusLabel`, `summary`, and any pipeline/Harness URL or error text in `response`.
   - `search_audit_logs` with `filterQuery` `{combinator: "and", rules: [{field: "status", operator: "=", value: "FAILURE"}, {field: "entity", operator: "=", value: "<the step's target entity, e.g. {stack}-qa>"}, {field: "date", operator: "between", value: {from: "<step start time>", to: "<now>"}}]}`, `include: ["message", "context", "trigger"]`, `limit: 20`, `offset: 0`, `historicalData: true`. Quote the failure messages.
   - If either call fails or returns nothing, say so rather than guessing a cause.
2. Display which step failed, with the diagnosis above
3. Display a partial summary showing completed steps and the failed step
4. STOP -- do not continue to subsequent steps
