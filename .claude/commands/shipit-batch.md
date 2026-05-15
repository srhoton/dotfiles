You are a multi-stack deployment orchestrator. Ship the following stacks IN PARALLEL through the full 8-stage Port.io pipeline: $ARGUMENTS

`$ARGUMENTS` is a comma-separated list of stack names (e.g., `mig-start-mg-fun,mig-wor-mg-fun,mig-usr-mg-fun`).

**IMPORTANT: Use Port.io MCP tools for ALL operations. Do NOT use Bash for Port.io interactions.**

---

## Step 0: Parse and Validate

1. Split `$ARGUMENTS` on commas, trim whitespace, deduplicate.
2. For each stack, look up `<stack>-dev` in the `stack_environment_status` blueprint and capture its `short_sha` as `TARGET_SHA[<stack>]`.
3. If any stack's dev entity is missing or has no `short_sha`, list those and STOP.
4. Display the launch table:
   ```
   Launching shipit-batch for N stacks:
   
   Stack                  | TARGET_SHA
   mig-start-mg-fun       | f776445
   mig-wor-mg-fun         | 9ff10f8
   mig-usr-mg-fun         | c872b3b
   ```

---

## Step 1: Dispatch Subagents in Parallel

In a SINGLE message, send one `Task` tool call per stack using `subagent_type: general-purpose`. Each subagent gets this prompt (template — substitute `{stack}` and `{target_sha}`):

```
You are shipping a single stack: {stack} (expected SHA: {target_sha}).

Execute the canonical 8-stage Port.io shipit pipeline EXACTLY as defined in /Users/steverhoton/.claude/commands/shipit.md. Use Port.io MCP tools only.

After EACH step, output exactly one line to your final response in this format:
  STATUS: stack={stack} step=<1-8> name=<step-name> state=<IN_PROGRESS|SUCCESS|FAILED|SKIPPED> detail=<short message>

When all 8 steps are done (or any fails), output:
  FINAL: stack={stack} outcome=<SUCCESS|FAILED> failed_step=<N or -> summary=<one-line>

Do NOT include narrative prose, full transcripts, or pipeline URLs in your output. The controller will dedupe and tabulate.

Use the SHA verification rules from shipit.md — after every deploy step (1, 4, 6), poll the target entity until short_sha == {target_sha} before proceeding.

For step 6 (Deploy to Prod), auto-approve any deployment-blueprint entities matching this stack with approval_status=AWAITING_APPROVAL.

Stop immediately on any FAILED step.
```

All subagent dispatches happen in **the same message** so they run concurrently.

---

## Step 2: Single Refreshing Dashboard

While subagents run, maintain ONE status table that you re-print as state changes. Initial state:

```
╭──────────────────────────────────────────────────────────────╮
│ shipit-batch — N stacks                                       │
├─────────────────────┬─────────────────────┬─────────────────┤
│ Stack               │ Stage               │ State            │
├─────────────────────┼─────────────────────┼─────────────────┤
│ mig-start-mg-fun    │ 0/8 pending         │ —                │
│ mig-wor-mg-fun      │ 0/8 pending         │ —                │
│ mig-usr-mg-fun      │ 0/8 pending         │ —                │
╰─────────────────────┴─────────────────────┴─────────────────╯
```

As subagents emit `STATUS:` lines, update the table cell and reprint ONLY when a state changes (don't reprint on identical state). For long IN_PROGRESS waits, use `run_in_background: true` on any internal polling Bash so refreshes don't stall.

---

## Step 3: Final Summary

Once all subagents have emitted `FINAL:`, print:

```
shipit-batch complete: N stacks

Stack                  | Outcome   | Failed step
mig-start-mg-fun       | SUCCESS   | —
mig-wor-mg-fun         | SUCCESS   | —
mig-usr-mg-fun         | FAILED    | 2/8 Promote Artifacts

Failures:
- mig-usr-mg-fun @ Promote Artifacts: <subagent failure summary>
```

If all SUCCESS, omit the "Failures" block.

---

## Constraints

- Do NOT use Bash sleep loops in the controller — let subagents do their own polling.
- Do NOT paste subagent transcripts in chat. Only the dashboard and final summary are user-visible.
- One stack failure does not cancel others — they all run to completion.
- Per CLAUDE.md Output Token Discipline: dashboard + summary only, no narrative prose.
