Report the live security and dependency posture of a Port.io stack using real scan data (Harness/Semgrep/Checkov/Trivy), not a static code read.

`$ARGUMENTS`: `<stack> [env]`.
- `<stack>` is the stack name (e.g. `mig-wor-mg-fun`). If empty, default to `basename "$PWD"`; if that isn't a Port stack, ask the user.
- `[env]` is optional (default `dev`) and is only used to report the current built SHA for reference.

**This is read-only. Use the Port MCP for all reads. Never trigger an action.** It complements the static `reviewitsec`/`security-reviewer` (which read code) with the actual scanner findings recorded per build.

Procedure:

1. Reference SHA (context only): `list_entities` on `stack_environment_status` for `<stack>-<env>`, read `short_sha`. Note it in the output so the reader can see whether findings sit on the current build. If the Port MCP is unavailable, say so and stop. If the stack entity doesn't exist, report that `<stack>` isn't a Port stack and stop.

2. Call `list_blueprints` for the finding blueprints once if you don't already have their schema this session (the MCP requires exact property/enum keys — guessing 422s the whole call).

3. Query **open** findings scoped to the stack. `severity_code` ∈ `Critical|High|Medium|Low|Info`; `status` ∈ `open|fixed|suppressed` — always filter `status = open`.
   - `cve_finding` — filter `{property: stack_id, =, <stack>}` + `{property: status, =, open}`. `groupBy severity_code` with `countOnly` for the headline counts, then list Critical/High with `cve_id`, `vulnerable_package`, `fixed_version`, `cvss_score`, `short_sha`.
   - `sast_finding` — same filter shape. List Critical/High with `rule_title`, `file_name`:`line_start`, `cwe`.
   - `secret_finding` — same filter shape. List **all** open (secrets always matter) with `file_name`:`line_start`, `rule_title`, `source_tool`.
   - `misconfig_finding` — its `stack_id` is a non-filterable calculation prop, and `list_entities` takes a single flat combinator (no nested rule groups). Run **two** `combinator: and` queries — `{stack_id_from_build = <stack>, status = open}` and `{stack_id_from_tf_run = <stack>, status = open}` — then union the results and de-duplicate by `harness_issue_id`. (A single flat `or` would OR the `status` rule in too and match every open misconfig org-wide.) List Critical/High with `rule_id`, `resource`, `file_name`, `source_tool`.
   - `dependency` — scope by the **relation**: `{relation: stack, =, <stack>}`. `groupBy severity`, then list entries whose `severity` ∈ `eol|major|non-compliant|drifted` with `ecosystem`, `declared_value` → `reference_value`. (`severity` may be null for compliant deps — ignore nulls.)
   - `security_exception` — filter `{property: stack_id, =, <stack>}` (the required `stack_id` property, not the optional `stack` relation) + `{property: status, =, active}` (its status enum is `active|expired|revoked`, NOT open/fixed/suppressed). Each active exception suppresses ticketing for a `finding_type` + `finding_key`; cross matching findings off so already-accepted risk isn't reported as live.

4. Output a compact severity-ranked summary per category with counts, then a verdict line, e.g.:
   `⚠️ mig-wor-mg-fun @ f4e828f: 2 Critical + 6 High CVEs, 0 open secrets, 0 misconfigs, 5 major-drifted deps — resolve Criticals before shipping.`
   or `✅ <stack> @ <sha>: no open Critical/High findings; deps compliant.`

5. If the full detail would exceed ~150 lines, write it to `~/.claude/scratch/<stack>/secscan-<ISO8601>.md` (`mkdir -p` on demand) and post only the counts + verdict + file path, per the Output Token Discipline rule. (Scratch is scoped by **stack** here — a deliberate override of that rule's `<repo-basename>` default, since this command targets a Port stack, not the cwd repo.)
