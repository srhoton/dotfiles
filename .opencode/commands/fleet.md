---
description: Fleet controller for multi-repo refactors. Apply the same change across many repos in parallel, with each repo getting its own context-isolated subagent.
---

You are a fleet controller for multi-repo refactors. Apply the same change across many repos IN PARALLEL, with each repo getting its own context-isolated subagent.

`$ARGUMENTS` should be one of these forms:
- `<spec-file-path> <repo1>,<repo2>,...` — explicit list
- `<spec-file-path> <glob>` — e.g. `~/git/*-svc`
- (empty) — prompt the user for both inputs

**Default policy: do NOT auto-ship.** Each subagent stops at PR creation. User triggers `/shipit` or `/shipit-batch` manually after PRs merge.

---

## Step 0: Parse Inputs

1. Determine the spec file path and list of repo paths.
2. If a glob was given, expand it: `ls -d <glob>`.
3. Read the spec file once at the controller level; cache its contents to pass to each subagent (don't make each subagent re-read it).
4. Display the launch table:
   ```
   Fleet refactor — N repos
   Spec: <path>
   
   Repo
   ath-rebac-svc
   ath-member-fun
   bil-invoice-svc
   ...
   ```
5. Ask the user: "Proceed with N parallel subagents?" — on "Show me the spec first", print the spec contents and ask again.

---

## Step 1: Dispatch Subagents in Parallel

In a SINGLE message, send one `Task` tool call per repo. Each subagent prompt template (substitute `{repo_path}` and embed the cached spec):

```
You are working on a single repo: {repo_path}. Apply the following refactor:

---
{spec contents}
---

Execute this workflow:

1. `cd {repo_path} && git fetch origin && git checkout master && git pull` (or `main` if applicable).
2. Run the premise-verifier subagent with the spec as input. If verdict is "STOP — premise refuted", stop immediately and report:
     RESULT: repo={repo_path} outcome=REFUTED reason=<one-line>
3. Create a feature branch named after the spec slug (e.g., `feature/projid-routing`).
4. Implement the refactor across files. Follow existing patterns; consult sibling implementations if uncertain.
5. Run the project test suite. Fix until green (max 3 attempts per failing test).
6. Run autonomous review-and-fix loop. Auto-fix CRITICAL+HIGH. Max 5 iterations.
7. Commit with `git notes`, push, open a PR via `gh pr create --body-file <tmpfile>`.
8. STOP at PR creation. Do NOT trigger /shipit.

Report ONE final line: RESULT: repo={repo_path} outcome=<SUCCESS|REFUTED|TEST_FAIL|REVIEW_STUCK|HUMAN_NEEDED|ERROR> branch=<branch-or--> pr=<#N-or--> reason=<one-line>

Output only the RESULT line as your final response.
```

All Task dispatches happen in **the same message** so they run concurrently.

---

## Step 2: Status Dashboard

While subagents work, maintain ONE refreshing table:

```
╭───────────────────────────────────────────────────────────────────────────╮
│ Fleet refactor — N repos                                                   │
├──────────────────────┬──────────┬──────────────────────┬──────┬───────────┤
│ Repo                 │ Premise  │ Branch               │ PR   │ Outcome   │
├──────────────────────┼──────────┼──────────────────────┼──────┼───────────┤
│ ath-rebac-svc        │ ✓        │ feature/projid       │ #88  │ SUCCESS   │
│ ath-member-fun       │ REFUTED  │ —                    │ —    │ REFUTED   │
│ bil-invoice-svc      │ ✓        │ feature/projid       │ —    │ REVIEW    │
╰──────────────────────┴──────────┴──────────────────────┴──────┴───────────╯
```

Reprint only on state change.

Outcome legend:
- `SUCCESS` — PR created, ready for human review
- `REFUTED` — premise verifier rejected; spec didn't apply to this repo
- `TEST_FAIL` — couldn't get tests green after 3 attempts
- `REVIEW_STUCK` — auto-fix loop hit 5 iterations without converging
- `HUMAN_NEEDED` — REQUIRES_HUMAN_JUDGMENT finding requires escalation
- `ERROR` — subagent encountered an unexpected error

---

## Step 3: Final Aggregate Report

When all subagents have reported their final `RESULT:` line, print:

```
fleet complete: N repos

Repo                  | Outcome    | PR
ath-rebac-svc         | SUCCESS    | https://github.com/<org>/<repo>/pull/88
bil-invoice-svc       | SUCCESS    | https://github.com/<org>/<repo>/pull/12
ath-member-fun        | REFUTED    | —
cus-profile-svc       | REVIEW_STUCK | —

Summary: 2 SUCCESS, 1 REFUTED, 1 REVIEW_STUCK

Refusals & blockers requiring action:
- ath-member-fun: <reason>
- cus-profile-svc: <reason>
```

---

## Constraints

- Each subagent runs in its own context window — the controller never sees their full transcripts, only RESULT lines.
- Failures don't cascade — one bad repo continues all others.
- Do NOT auto-ship. PRs created are the deliverable; user ships manually post-merge.
- All PR bodies use `--body-file <tmpfile>`, not inline heredoc.
