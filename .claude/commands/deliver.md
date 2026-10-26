---
description: "Take a Jira ticket all the way to a merge-ready, green-CI PR, pausing once at plan approval."
disable-model-invocation: true
---
You are a ticket-to-PR delivery pipeline. Your job is to take Jira ticket `$ARGUMENTS` all the way to a merge-ready, green-CI PR with the Jira ticket updated — pausing exactly once, at plan approval. Deployment (`/shipit`) is NOT part of this command; it stays a separate, user-triggered step.

This command composes existing assets. Where it says "follow `<file>`", read that file and execute its steps — do not improvise a variant.

---

## Phase 1: Evidence Plan (ends with a STOP for approval)

1. Read the Jira ticket `$ARGUMENTS`, its epic, and any linked tickets/PRs — via the Atlassian MCP tools (`mcp__claude_ai_Atlassian__getJiraIssue`; `getConfluenceContent` for linked specs — `getConfluencePage` on a v1 server). If the Atlassian MCP server is not connected this session, say so and ask — never fall back to browser automation for Jira/Confluence.
2. **Premise verification**: dispatch the `premise-verifier` agent against the ticket's factual claims (services, files, symbols, library versions it references). Additionally, validate data claims (counts, rates, schemas) against live sources — Athena via `aws-data-analytics:querying-data-lake`, DynamoDB, S3 — per CLAUDE.md Data Validation. Ticket text and stale git history have both been wrong before; report each claim as CONFIRMED / REFUTED / UNVERIFIABLE with the evidence. If a load-bearing premise is REFUTED, stop and surface it — do not plan against it.
3. **Scope**: work in the single repo the ticket targets. If implementation appears to require a second repo, STOP and ask before exploring it. Any subagent you dispatch gets an explicit repo/directory scope and must return and ask rather than expand.
4. **Plan**: write the implementation plan (files to change, approach, test plan) including an explicit **Assumptions** list. If the change introduces a new mechanism or layer touching durable state, retries/rate limits, migration semantics, or multi-step orchestration, it trips the CLAUDE.md **Design Gate**: write the design into the plan file and dispatch the `functional-reviewer` against it to attack failure paths, idempotency, and re-run safety — before any code.
5. **STOP.** Present the plan + premise-verification table and get the user's approval. This is the one human gate; historically the corrections that mattered (mode-switch vs additive, schema placement, edge cases) all landed here.

## Phase 2: Implement

You orchestrate this phase; the `implementer` agent writes the code. Do not write the implementation yourself, and do not pass `model` on the dispatch.

1. Branch off the latest default branch (never commit to it directly).
2. Dispatch the `implementer` agent. The prompt carries:
   - the approved plan file path, plus the premise-verification table;
   - the repo root and the files/directories it may change (the Phase 1 scope);
   - the **Gates** below, verbatim.
3. **Gates** (all must pass before Phase 3):
   - Typecheck + lint + **full test suite**: `~/.claude/bin/repo-gate`, which must end `REPO-GATE: PASS`. If that line lists skipped gates, run each skipped gate by hand, or say why it doesn't apply.
   - **Mutation-probe every new/modified test** with `~/.claude/bin/mutation-probe --test '<scoped test cmd>' <changed-prod-file>...` (add `--together` for multi-file atomic fixes). It reverts the production change via file copy — never `git checkout`/`git restore` — confirms the test FAILS against unfixed code, and restores. Any test it reports VACUOUS is rewritten and re-probed. Report the probe output.
   - **Deterministic test doubles only**: no `Math.random`, `Date.now()`, argless `new Date()`, or real timers in stubs — CI runs under coverage and flakes on them.
4. When the implementer returns:
   - **BLOCKERS that are plan problems:** revise the plan yourself. A design-level change goes back through the Design Gate before you re-dispatch. Re-dispatch with the revised plan and the prior report's concrete errors, never an identical prompt.
   - **Otherwise, verify instead of trusting the report:** re-run `~/.claude/bin/repo-gate` yourself, and read the diff.
5. Self-check the diff for scope creep (unrequested layers, cleanup handlers, defensive frameworks). Send any descoping back to the implementer as a fix round; don't edit it yourself.

## Phase 3: Review

Follow `~/.claude/commands/review.md` exactly — mechanical gate, five parallel reviewers, fix discipline, the 2-fix-iteration hard cap, diff-growth tripwire, and descope escalation are all defined there and are binding here.

## Phase 4: Ship

1. Merge or rebase onto the latest `origin/<default branch>` and re-run the full test suite, so concurrent-merge breakage surfaces locally (CLAUDE.md PR rules).
2. Follow `~/.claude/commands/trueup.md`: commit (message via tempfile + `git commit -F`), attach session prompts via git notes, push, and open the PR with `gh pr create --body-file <tmpfile>` — the body describing the full diff against the target branch.
3. **Jira** (Atlassian MCP tools, never browser automation): comment the PR link + a one-paragraph summary on `$ARGUMENTS` with `addOrEditJiraIssueComment`; ensure the ticket is linked under its epic (`editJiraIssue`/`createJiraIssueLink`); transition status with `listJiraIssueTransitions` + `transitionJiraIssue` if the workflow expects it. (Rovo MCP v2 names; a v1 server lists these as `addCommentToJiraIssue`, `createIssueLink`, `getTransitionsForJiraIssue`.)
4. **Monitor CI to green** with `~/.claude/bin/pr-ci-wait <PR#>`. It polls with backoff, needs a terminal state twice before trusting it, and prints the failed jobs' log tails. Exit codes: 0 green, 1 failed, 2 timed out, 3 no checks reported, 4 `gh` itself kept failing. On 2-4, report and escalate; don't start another wait loop. If CI fails, the implementer fixes it, then push (the Phase 3 cap logic applies — don't grind past 2 fix rounds without escalating).
5. **Review comments**: for each incoming comment, verify the claim against code/data first — refute with evidence if it doesn't hold, fix it if it does (fix discipline applies) — and post a threaded reply on every thread.

## Wrap-up

Close with a short summary (what changed with `file:line` refs, evidence, PR + Jira links) and a bulleted **suggested next steps** list (e.g. `/shipit <stack>` once approved). Do not end on a question.
