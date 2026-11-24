---
name: impl-plan
description: Build, publish and refresh a phased implementation plan as a claude artifact with live PR-status colours (green completed, yellow PR out, orange design gate, red not started), from a claude artifact URL, an apex TDS path, or the current session's design. Use when the user asks for an ordered or phased implementation plan, a plan "in plain english", or to "review the PRs, update the plan and colour code it". Args: `<source> [--ticket <EPIC-KEY|PROJECT>]` to build, or `--refresh <artifact-url>` to re-score and republish.
argument-hint: "<artifact-url | apex TDS path> [--ticket <EPIC-KEY|PROJECT>]  |  --refresh <artifact-url>"
---

# /impl-plan

The plan is **data**: you write `plan.json` once (schema: `~/.claude/skills/impl-plan/plan.schema.json`). Two scripts do the rest at no model cost:

- `~/.claude/bin/impl-plan-status plan.json [--discover] [--write]` validates, reads PR states from GitHub, and writes each step's `status` and `statusWhy`. Never write those two fields (or `stale`, `prStates`, `warnings`) yourself.
- `~/.claude/bin/impl-plan-render plan.json > index.html` renders the one fixed page template (an HTML fragment; the Artifact publisher adds the doctype/head/body). Don't hand-write or hand-edit HTML.

Status rules (script, in order): orange design gate (required and not approved, even with PRs) > green (`doneWhen: merged` with every PR merged, or `doneWhen: manual` with `done: true`) > yellow (any PR open, or a manual step with PRs not marked done) > red (no PRs). Merged means green, so a deploy or live check is its own `doneWhen: manual` step.

Parse `$ARGUMENTS`: `--refresh <url>` goes to step 7; otherwise `<source>` (optional) and `--ticket <key>`.

## Workflow

1. **Read the source in full.** The named artifact is the research: don't fan out to other repos or sources.
   - Claude artifact URL: `Artifact action:read`. If it has a `plan.json`, this is a refresh: go to step 7.
   - Apex TDS: apex's default branch is `main`. Run `git -C ~/git/apex fetch && git -C ~/git/apex log origin/HEAD -1` first, and read the TDS from `origin/HEAD` with `git -C ~/git/apex show origin/HEAD:<path>` so a stale local checkout doesn't matter (don't pull or modify the user's checkout). TDSs live at `domains/<domain>/design/<slug>/design.md`; locate one with `git -C ~/git/apex ls-tree -r --name-only origin/HEAD domains | grep -E '/design/[^/]+/design\.md$'`. The old path `domains/<domain>/tds/<slug>.md` may hold a "# Moved" stub pointing at the new path: follow it. Component and Service Design and Data Models and API Contracts become the work, Acceptance Criteria become each step's done-when, Applicable ADRs become step notes.
   - No argument: the design in the current session.
2. **Premise-check the repos.** For every repo named, run `gh repo view fullbay/<repo> --json isArchived,pushedAt`. Set `exists: true` or `exists: false` (new repo). If a repo is archived, stop and ask which repo replaced it.
   - Repos may live outside `fullbay` (e.g. `fb-shared-infra/OpenSearchIndexer`): use `owner/repo` as the repo name in that case.
   - If the source names a repo that doesn't exist but an obviously equivalent one does (search `gh search repos <keyword> --owner fullbay`), use the real one, say so in the step's `work`, and add an open question to correct the source.
   - When the source and the built code disagree (check the repos' merged PRs), record the disagreement as an open question. Don't silently follow either.
3. **Draft `plan.json`.**
   - Steps are ticket-sized, one PR per repo where possible, grouped into phases by dependency. `plain` is the plain-English summary: what the step does, no jargon.
   - Set `designGate.required` by CLAUDE.md's Design Gate criteria: a new mechanism touching durable state, retry or quota logic, migration semantics or orchestration. Give a one-line `reason`. `approved` is the approval date or `null`.
   - Gaps and ambiguities in the source become `questions`, each with the step ids it `blocks`. Don't ask them interactively.
   - `plan.title` is a 2-4 word name. `plan.slug` names the scratch directory.
4. **Validate and score:** `~/.claude/bin/impl-plan-status plan.json --discover --write`. Exit 2 names the bad field: fix the plan and rerun. `--discover` only prints suggested PRs; confirm each against its ticket before adding it to a step's `prs`, then rerun. Exit 1 means gh failed: the steps that need it are marked stale (never green unless every readable PR is merged and every unreadable PR was last seen merged) and each unreadable PR is a "PR state unknown" warning: report it, don't paper over it. Exit 2 can also mean `plan.json` changed while it was being scored: nothing was written, rerun.
5. **Render:** `~/.claude/bin/impl-plan-render plan.json > index.html`.
6. **Publish** with the Artifact tool. Include `plan.json` as a supporting file next to `index.html`, so a later session can refresh from the URL alone. Keep a local copy of both at `~/.claude/scratch/plans/<slug>/` (`mkdir -p`). Load `artifact-design` once, as the tool requires; the template is fixed, so no new design pass is needed.
7. **`--refresh <url>`:**
   - `Artifact read path:"plan.json"` and save it to `~/.claude/scratch/plans/<slug>/plan.json`;
   - run `impl-plan-status plan.json --discover --write`, then `impl-plan-render`;
   - republish to the same URL;
   - report only the changes, as a compact table: step, old -> new status, why. If nothing changed, say "no changes".
   - Step in only for what the script flags: a suggested PR it couldn't place, or a `manual` step (ask whether it is done, then set `done`). Everything else is script output.
8. **`--ticket <key>`** (an epic key or a project): this is outward-facing, so confirm first.
   - Build the story list in the main loop: one story per step with its work, repos, plain English, and `dependsOn` as "is blocked by" links. Show the list to the user and wait for confirmation. Don't create anything before then.
   - After confirmation, one `model: haiku` agent creates the stories through the Atlassian MCP (CLAUDE.md bulk-Jira rule) and returns one line per story (step id, key).
   - Write the keys into each step's `tickets`, then rerun steps 4-6 (re-score, re-render, republish).

## Rules

- `plan.json` is the source of truth; the HTML is disposable. To change content, edit `plan.json` and re-render.
- Fixtures, examples and tests in the dotfiles mirror use made-up repos and ticket keys only.
- Don't create Jira tickets, or publish anywhere but the claude artifact, unless the user asked for it in this run.
