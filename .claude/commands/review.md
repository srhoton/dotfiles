You are a comprehensive local code reviewer. Your job is to run a full multi-pass review on the current working directory's changes and give the user control over fixing findings.

Follow these steps exactly:

---

## Step 1: Detect Changed Files

Determine what files have changed relative to the main branch:

```bash
# Get the default branch name
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")

# Changed files on this branch vs default
git diff --name-only "$DEFAULT_BRANCH"...HEAD 2>/dev/null || true

# Unstaged changes
git diff --name-only

# Staged changes
git diff --name-only --cached
```

Combine and deduplicate all changed files into a single list. If `$ARGUMENTS` is provided, filter the list to only files matching those paths or patterns.

If no changed files are found, report: "No changes detected. Nothing to review." and stop.

Display the list of files that will be reviewed.

---

## Step 1.5: Mechanical Gate (run BEFORE dispatching any reviewer)

Deterministic checks are cheaper, faster, and more reliable than LLM reviewers, and spending reviewer attention on lint/type errors is precisely what lets judgment-level bugs slip to a later round. Run these first and fix what they find before any agent is dispatched.

```bash
# 1. Type check (whatever the project actually uses)
#    Node: prefer the project's typecheck/type-check script, else `npx tsc --noEmit`
#    Java: ./gradlew compileJava    Go: go build ./...    Python: mypy
# 2. Deterministic diff checks: eslint errors on changed files + ReDoS heuristic
~/.claude/bin/vet-diff
```

Report anything they surface as findings **before** Step 2, and fix them first. Notes:
- `vet-diff` is scoped to changed files (and, for the regex check, added lines only), so pre-existing debt elsewhere never blocks you.
- It reports `SKIPPED` rather than failing when a repo has no eslint config — that is expected in several repos here, not an error.
- If the gate is clean, say so in one line and continue to Step 2.

---

## Step 2: Run Reviews via the review-fanout Workflow

Invoke the **Workflow tool** with the saved orchestration script (this slash command IS your explicit opt-in to run it):

- `scriptPath`: `~/.claude/workflows/review-fanout.js`
- `args` (JSON object, not a string):
  - `repoRoot`: absolute repo root
  - `files`: the changed-file list from Step 1
  - `intent`: the user's stated requirements — the contents of `sdlc-plan.md` if one exists in the repo root, otherwise recent commit messages on this branch

The workflow runs the five specialist reviewers (functional, code-quality, adr-compliance, performance, data-side-effects) in parallel with schema-validated findings, dedupes by file:line, checks the diff against the defect-class checklist (`~/.claude/knowledge/defect-classes.md`), then adversarially verifies each CRITICAL/HIGH finding with a skeptic agent. It returns `{ actionable, informational, refuted, reviewersSkipped }`.

- `actionable` findings carry `verified: true/false` — `false` means the skeptic errored or the finding was beyond the verify cap; treat those with extra suspicion, don't drop them.
- `refuted` findings were disproved with cited evidence — do NOT act on them, but include them in the report so the user can spot-check the refutations.
- If `reviewersSkipped` is non-empty, say so in the report.

**Fallback — Workflow tool unavailable this session:** dispatch five parallel Task calls to the same five subagent types, each prompt containing the repo root + changed-file list, these scope bounds — (1) that list is the agent's ENTIRE scope, (2) do not explore sibling repos or spawn further agents, (3) report out-of-scope evidence gaps as notes instead of expanding — and a request for delimited findings blocks (severity CRITICAL/HIGH/MEDIUM/LOW, file, line, description). Instruct the functional and data-side-effects reviewers to also check the diff against `~/.claude/knowledge/defect-classes.md`. Then dedup by file:line yourself.

---

## Step 3: Display

Using the workflow's returned structure (or your own aggregation in the fallback case), display ALL findings:

```
## Actionable Findings (CRITICAL/HIGH)

[1] CRITICAL | src/main/java/Foo.java:42 | Null pointer dereference on unchecked input | functional
[2] HIGH     | src/components/Bar.tsx:88  | Missing input sanitization before render    | quality
[3] HIGH     | src/service/Query.java:15  | N+1 query pattern in loop                   | performance

## Informational Findings (MEDIUM/LOW)

[4] MEDIUM   | src/utils/helpers.ts:30    | Consider extracting shared constant          | quality
[5] LOW      | src/model/User.java:12     | Zustand store could use selectors            | adr
```

If the workflow returned `refuted` findings, add a `## Refuted by verification` section listing each with its refutation — for user spot-checking, not for fixing.

If there are **zero** CRITICAL/HIGH findings, report: "Clean review — no critical or high issues found." Display the informational summary if any, and stop.

---

## Step 4: Offer to Fix

If there are actionable findings, use `AskUserQuestion` with this question:
- Question: "Would you like me to fix the actionable findings?"
- Options:
  - "Fix all" — fix every CRITICAL and HIGH finding
  - "Let me pick" — user types comma-separated numbers in the freeform/Other field
  - "Skip" — just keep the report, no fixes

---

## Step 5: Apply Fixes and Re-Review

If fixes are requested:

### Fix discipline (applies to every fix, every iteration)

Session evidence shows the review loop's dominant failure modes are fix-side, not review-side. These four rules are mandatory:

- **Class, not site**: when a finding is anchored at one call site, enumerate all sibling sites before fixing (LSP find-references or grep for the symbol/pattern) and fix or explicitly clear each one. The fix recap must list that enumeration ("fixed at X; checked Y, Z — unaffected because …"). Fixing only the reported site is the single most repeated cause of extra review rounds.
- **One minimal fix per defect**: never ship a second fix for the same defect without first demonstrating the first alone is insufficient. Two fixes bundled for one bug is how pure regressions ship.
- **Never trade loud for silent**: a fix must not convert a detectable failure into a silently-recorded success (e.g. latching a clean status over an unhandled path). If the choice is between an uncaught error and a quiet wrong answer, keep the error.
- **Evidence-backed recap**: every CRITICAL/HIGH fix ships with an executed probe — a test or script that failed before the fix and passes after — not a prose claim. For test-covered fixes, run the probe with `~/.claude/bin/mutation-probe --test '<scoped test cmd>' <fix-file>...` — it reverts the fix via file copy (never `git checkout`), proves the test fails without it, and flags VACUOUS tests. Probes must exercise shipped config values; a test whose stubs invert the shipped configuration structurally cannot catch the bug it claims to cover. Reviewers will refute unverified recaps, and that refutation costs a full round.

### Fix loop

1. Record the current diff size before fixing: `git diff --shortstat "$DEFAULT_BRANCH"...HEAD`
2. Apply the selected fixes following the fix discipline above
3. **Re-run the Step 1.5 mechanical gate first** (typecheck + `~/.claude/bin/vet-diff`). This is the step that catches fix-induced regressions deterministically — a fix that introduces a lint error, a type error, or a ReDoS-shaped regex is caught here in seconds, instead of costing a whole LLM review round to rediscover. Fix anything it reports before continuing.
4. Run the full test suite to verify fixes don't break anything
5. Re-invoke the review-fanout workflow on the changed files (same as Step 2, fresh run — files changed, so no cache reuse) — the LLM re-review remains the backstop for judgment-level regressions the gate cannot see
6. Display updated findings and the new `git diff --shortstat`

### Termination and descope escalation (hard rules — these are enforced, not advisory)

- **Hard cap: 2 fix iterations.** If CRITICAL/HIGH findings remain after the second fix iteration, STOP. Do not fix again, do not start a third iteration on your own authority. Use `AskUserQuestion`:
  - Question: "The change has failed review N times. How should I proceed?"
  - Options: **"Ship passing layer"** (keep what passes review; revert/defer the failing parts), **"Revert failing layer"**, **"Split the change"** (separate branch/PR for the contested part), **"Continue fixing"** (grants at most 2 more iterations, once — after which stopping is unconditional).
  - Stopping here is required behavior, not premature stopping — it falls under CLAUDE.md's "Escalate instead of grinding" rule, same as the `/shipit` retry budget.
- **Diff-growth tripwire**: compare the `--shortstat` recorded each round. If the net diff has **grown for two consecutive fix iterations**, the loop is redesigning under review, not fixing — trigger the same escalation immediately, regardless of iteration count. Historical sessions grew +2784 → +4124 lines over 11 rounds before a manual descope resolved it in one.
- **Layer-separation heuristic**: if blocking findings concentrate in one separable layer/feature while the rest of the change passes round after round, proactively propose shipping the passing layer and reverting or deferring the failing one — do not wait for the cap to force it.
- **Design-failure signal**: a layer that fails successive rounds *for a different structural reason each time* is a design problem, not a bug backlog. Patching it further is waste — route it through the Design Gate in CLAUDE.md (plan-file design + adversarial design review) before any more code.

After the final iteration, display a summary: "Review complete. Fixed N findings across M iterations. K actionable findings remain."
