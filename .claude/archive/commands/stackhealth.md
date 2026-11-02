Report the service-health and ship-readiness of a Port.io stack from its live `stack` entity — coverage, scorecard level, DORA/ops metrics, and dependency drift.

`$ARGUMENTS` is the stack name (e.g. `mig-wor-mg-fun`). If empty, default to `basename "$PWD"`; if that isn't a Port stack, ask the user.

**This is read-only. Use the Port MCP for all reads. Never trigger an action.**

Procedure:

1. `list_entities` on the `stack` blueprint for `[<stack>]` with `include`:
   `current_line_coverage`, `current_branch_coverage`, `lifecycle_state`, `change_failure_rate`, `cfr_incident_based`, `deployment_count_30_days`, `production_deployments_count_30_days`, `failed_production_deployments_30_days`, `incidents_30_days`, `avg_lead_time_to_prod_hours`, `major_drift_count`, `eol_dep_count`, `non_compliant_count`, `last_successful_build_at`, `auto_build_enabled`, and the `stackHealth` scorecard.
   - If the Port MCP is unavailable, say so and stop. If the stack entity doesn't exist, report that `<stack>` isn't a Port stack and stop.

2. **Scorecard** (`stackHealth`, levels Basic → Bronze → Silver → Gold): report the current `level` and every rule whose `status = FAILURE`, with the concrete gap to the next level. Read the failing rule's condition to state the gap precisely, e.g. "branch coverage 79.2% vs the 80% `branchCoverageGold` gate — 0.8% short" or "`hasSynthetic` failing — no canary configured". Ignore rules that are N/A for the stack's `stack_type`.

3. **DORA / ops**: change failure rate (`change_failure_rate`, and `cfr_incident_based`), `production_deployments_count_30_days`, `failed_production_deployments_30_days`, `incidents_30_days`, `avg_lead_time_to_prod_hours`, `last_successful_build_at`, `lifecycle_state`.

4. **Drift**: `major_drift_count`, `eol_dep_count`, `non_compliant_count`. If any are > 0, point the reader to `/secscan <stack>` for the per-dependency detail.

5. Optional current state: `list_entities` on `stack_environment_status` for `<stack>-dev` and `<stack>-prod`, include `promotable`, `integration_test_status`, `short_sha` — so the report shows whether the stack is currently promotable and tests are green.

6. Output a compact table/bullets and a one-line **ship-readiness verdict** (e.g. "Silver; coverage gates green; 5 major-drifted deps, 0 EOL; 0 incidents/30d — safe to ship, drift is non-blocking"). If detail would exceed ~150 lines, write it to `~/.claude/scratch/<stack>/stackhealth-<ISO8601>.md` and post the verdict + path, per the Output Token Discipline rule. (Scratch is scoped by **stack** here — a deliberate override of that rule's `<repo-basename>` default, since this command targets a Port stack, not the cwd repo.)
