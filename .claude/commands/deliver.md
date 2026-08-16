You are a ticket-to-PR delivery pipeline. Your job is to take Jira ticket `$ARGUMENTS` all the way to a merge-ready, green-CI PR with the Jira ticket updated — pausing exactly once, at plan approval. Deployment (`/shipit`) is NOT part of this command; it stays a separate, user-triggered step.

This command composes existing assets. Where it says "follow `<file>`", read that file and execute its steps — do not improvise a variant.

---

## Phase 1: Evidence Plan (ends with a STOP for approval)

1. Read the Jira ticket `$ARGUMENTS`, its epic, and any linked tickets/PRs.
2. **Premise verification**: dispatch the `premise-verifier` agent against the ticket's factual claims (services, files, symbols, library versions it references). Additionally, validate data claims (counts, rates, schemas) against live sources — Athena via `aws-data-analytics:querying-data-lake`, DynamoDB, S3 — per CLAUDE.md Data Validation. Ticket text and stale git history have both been wrong before; report each claim as CONFIRMED / REFUTED / UNVERIFIABLE with the evidence. If a load-bearing premise is REFUTED, stop and surface it — do not plan against it.
3. **Scope**: work in the single repo the ticket targets. If implementation appears to require a second repo, STOP and ask before exploring it. Any subagent you dispatch gets an explicit repo/directory scope and must return and ask rather than expand.
4. **Plan**: write the implementation plan (files to change, approach, test plan) including an explicit **Assumptions** list. If the change introduces a new mechanism or layer touching durable state, retries/rate limits, migration semantics, or multi-step orchestration, it trips the CLAUDE.md **Design Gate**: write the design into the plan file and dispatch the `functional-reviewer` against it to attack failure paths, idempotency, and re-run safety — before any code.
5. **STOP.** Present the plan + premise-verification table and get the user's approval. This is the one human gate; historically the corrections that mattered (mode-switch vs additive, schema placement, edge cases) all landed here.

## Phase 2: Implement

1. Branch off the latest default branch (never commit to it directly).
2. Implement with tests, following the language rules files and existing repo patterns (find 2-3 examples before inventing one).
3. **Gates** (all must pass before Phase 3):
   - Typecheck + lint + **full test suite** (`tsc --noEmit`/eslint, or `./gradlew build spotlessApply`, per repo).
   - **Mutation-probe every new/modified test**: temporarily revert the production change **via a file copy in the scratchpad — never `git checkout`/`git restore` on a dirty tree** — confirm the test FAILS against unfixed code, then restore. A test that passes against unfixed code is rewritten and re-probed. Report probe results.
   - **Deterministic test doubles only**: no `Math.random`, `Date.now()`, argless `new Date()`, or real timers in stubs — CI runs under coverage and flakes on them.
4. Self-check the diff for scope creep (unrequested layers, cleanup handlers, defensive frameworks) and descope it yourself before review.

## Phase 3: Review

Follow `~/.claude/commands/review.md` exactly — mechanical gate, five parallel reviewers, fix discipline, the 2-fix-iteration hard cap, diff-growth tripwire, and descope escalation are all defined there and are binding here.

## Phase 4: Ship

1. Merge or rebase onto the latest `origin/<default branch>` and re-run the full test suite, so concurrent-merge breakage surfaces locally (CLAUDE.md PR rules).
2. Follow `~/.claude/commands/trueup.md`: commit (message via tempfile + `git commit -F`), attach session prompts via git notes, push, and open the PR with `gh pr create --body-file <tmpfile>` — the body describing the full diff against the target branch.
3. **Jira**: comment the PR link + a one-paragraph summary on `$ARGUMENTS`; ensure the ticket is linked under its epic; transition status if the workflow expects it.
4. **Monitor CI to green.** Poll with backoff; if CI fails, fix and push (the Phase 3 cap logic applies — don't grind past 2 fix rounds without escalating).
5. **Review comments**: for each incoming comment, verify the claim against code/data first — refute with evidence if it doesn't hold, fix it if it does (fix discipline applies) — and post a threaded reply on every thread.

## Wrap-up

Close with a short summary (what changed with `file:line` refs, evidence, PR + Jira links) and a bulleted **suggested next steps** list (e.g. `/shipit <stack>` once approved). Do not end on a question.
