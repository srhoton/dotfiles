You are an autonomous review-and-fix loop. Run the multi-pass reviewers, auto-fix all CRITICAL and HIGH findings, and only stop when the code is clean (or human judgment is required).

Optional `$ARGUMENTS`: extra context for the reviewers (e.g., "treat as ADR-XYZ migration"). Leave blank otherwise.

---

## Step 1: Detect Changed Files

Same as `/review` Step 1:

```bash
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
git diff --name-only "$DEFAULT_BRANCH"...HEAD 2>/dev/null || true
git diff --name-only
git diff --name-only --cached
```

Combine and deduplicate. If no changed files, report "Nothing to ship — no changes." and stop.

---

## Step 2: Autonomous Fix Loop (max 5 iterations)

For iteration `i` from 1 to 5:

### 2a. Dispatch 4 reviewers in parallel (single message)

**Task A — functional-reviewer:**
Provide changed files. Instruct: review for functional correctness against the PR description / commit messages / `sdlc-plan.md` if present. Output findings with `severity`, `file`, `line`, `description`. **Add a `judgment_tag` field set to `AUTO_FIX` for mechanical issues or `REQUIRES_HUMAN_JUDGMENT` for architectural/multi-interpretation issues.**

**Task B — code-quality-reviewer:**
Same format and tagging.

**Task C — adr-compliance-reviewer:**
Same format. Use dynamic ADR loading from `~/git/architecture-decisions`. Same tagging.

**Task D — performance-reviewer:**
Same format and tagging.

### 2b. Aggregate

- Parse all findings into a single list.
- Bucket by severity (CRITICAL, HIGH, MEDIUM, LOW) AND by judgment_tag.
- **Actionable bucket** = severity ∈ {CRITICAL, HIGH} AND judgment_tag = AUTO_FIX
- **Escalation bucket** = severity ∈ {CRITICAL, HIGH} AND judgment_tag = REQUIRES_HUMAN_JUDGMENT
- **Informational bucket** = severity ∈ {MEDIUM, LOW} (any tag)

### 2c. Decision

- If **Actionable bucket is empty**:
  - If Escalation bucket is empty: clean — exit loop, proceed to Step 3 (commit).
  - If Escalation bucket has items: stop loop, surface escalations as a numbered list, ask user via `AskUserQuestion` whether to fix them or skip them. Then proceed to Step 3.
- If **Actionable bucket has items**:
  - Apply fixes for every actionable finding without prompting.
  - Run the project's test suite (`./gradlew test`, `bun test`, `pytest`, etc. — detect from project files).
  - If tests fail, fix until green (max 3 fix attempts per failed test). If still failing after 3, escalate via `AskUserQuestion`.
  - Continue to iteration `i+1`.

### 2d. Iteration cap

If `i == 5` and Actionable bucket is still non-empty, stop the loop. Report:
- Iterations attempted
- Remaining CRITICAL/HIGH findings (file:line + description only, no full code)
- Recommend manual intervention

---

## Step 3: Commit, Push, PR

Once the loop exits cleanly (or after escalation handling):

1. Stage all changes: `git add -A`
2. Generate a commit message summarizing the changes (terse — one-liner with bullet list of major changes).
3. Add a git note with the iteration count and a brief log of what was auto-fixed each iteration.
4. Push the branch.
5. Open a PR using `gh pr create --body-file <tmpfile>` (per CLAUDE.md heredoc rule). Body includes:
   - One-line summary
   - "Auto-fixed findings" section: count per category
   - "Escalated findings" section (if any): listed for human review
   - Test plan checkbox list
6. Output the PR URL.

**Do NOT trigger `/shipit`.** This command stops at PR creation. The user runs `/shipit <stack>` manually after the PR merges.

---

## Step 4: Final Summary

Display one final compact summary:

```
ship-when-clean complete

Iterations: 3
Auto-fixed: 12 (CRITICAL: 2, HIGH: 10)
Escalated: 1 (REQUIRES_HUMAN_JUDGMENT)
Informational (not fixed): 5 (MEDIUM: 3, LOW: 2)
PR: https://github.com/<org>/<repo>/pull/N
```

If iterations hit max without convergence, replace "complete" with "stopped at max iterations" and include the remaining findings.

---

## Constraints

- Per CLAUDE.md Output Token Discipline: no full code blocks in chat. File:line references only.
- Per CLAUDE.md Heredocs rule: PR body MUST go through `--body-file <tmpfile>`, not inline heredoc.
- Auto-fix only applies to AUTO_FIX-tagged findings; REQUIRES_HUMAN_JUDGMENT always escalates.
- Each iteration MUST re-run all 4 reviewers (don't trust that yesterday's pass means today's clean).
