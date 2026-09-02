You are a comprehensive PR reviewer. Your job is to review PR #$ARGUMENTS, post inline comments for critical/high findings, and give the user control over what gets posted.

**IMPORTANT: Use `gh` CLI for ALL GitHub operations. Do NOT use GitHub MCP tools.**

Follow these steps exactly:

---

## Step 1: Fetch PR Context

Run these commands to gather PR info:

```bash
# Get repo owner/name
REPO=$(gh repo view --json owner,name --jq '.owner.login + "/" + .name')

# Get PR details
gh pr view $ARGUMENTS --json title,body,headRefName,headRefOid,files

# Get the full diff
gh pr diff $ARGUMENTS
```

Save the PR title, body, head SHA, and list of changed files for use in later steps. Also save your current branch:

```bash
ORIGINAL_BRANCH=$(git branch --show-current)
```

Then checkout the PR:

```bash
gh pr checkout $ARGUMENTS
```

---

## Step 2: Run Reviews via the review-fanout Workflow

Invoke the **Workflow tool** with the saved orchestration script (this slash command IS your explicit opt-in to run it):

- `scriptPath`: `/Users/steverhoton/.claude/workflows/review-fanout.js`
- `args` (JSON object, not a string):
  - `repoRoot`: absolute repo root
  - `files`: the PR's changed-file list from Step 1
  - `intent`: the PR title and body ("Treat the PR description as the user's requirements")

The workflow runs the five specialist reviewers (functional, code-quality, adr-compliance, performance, data-side-effects) in parallel with schema-validated findings, dedupes by file:line, checks the diff against the defect-class checklist (`~/.claude/knowledge/defect-classes.md`), then adversarially verifies each CRITICAL/HIGH finding with a skeptic agent. It returns `{ actionable, informational, refuted, reviewersSkipped }`.

- `actionable` findings carry `verified: true/false` — `false` means the skeptic errored or the finding was beyond the verify cap; treat those with extra suspicion, don't drop them.
- `refuted` findings were disproved with cited evidence — never propose them as PR comments; show them in the terminal summary so the user can spot-check.
- If `reviewersSkipped` is non-empty, say so.

**Fallback — Workflow tool unavailable this session:** dispatch five parallel Task calls to the same five subagent types, each prompt containing the repo root + changed-file list (plus PR title/body for the functional reviewer), these scope bounds — (1) that list is the agent's ENTIRE scope, (2) do not explore sibling repos or spawn further agents, (3) report out-of-scope evidence gaps as notes instead of expanding — and a request for delimited findings blocks (severity CRITICAL/HIGH/MEDIUM/LOW, file, line, description). Instruct the functional and data-side-effects reviewers to also check the diff against `~/.claude/knowledge/defect-classes.md`. Then dedup by file:line yourself.

---

## Step 3: Prepare Comments

From the workflow's returned structure (or your own aggregation in the fallback case):

1. **Actionable** = the returned CRITICAL/HIGH findings that survived verification
2. **Informational** = MEDIUM and LOW findings
3. For each actionable finding, prepare an inline comment with:
   - `file`: relative path
   - `line`: line number
   - `body`: the finding description + suggested fix
   - `source`: "functional" / "quality" / "adr" / "performance" / "data-side-effects" / combination (e.g. "quality+performance")

Display the MEDIUM/LOW findings in the terminal as an informational summary (not proposed as PR comments).

If there are **zero** CRITICAL/HIGH findings, report: "Clean review — no critical or high issues found." Then display the informational summary if any, checkout the original branch, and stop.

---

## Step 4: Present Proposed Comments for Approval

Display ALL actionable findings as a numbered list:

```
[1] CRITICAL | src/main/java/Foo.java:42 | Null pointer dereference on unchecked input | functional
[2] HIGH     | src/components/Bar.tsx:88  | Missing input sanitization before render    | quality
[3] HIGH     | terraform/main.tf:15      | S3 bucket missing encryption configuration  | both
```

Then use `AskUserQuestion` with this question:
- Question: "Which comments would you like to post as inline review comments on PR #$ARGUMENTS?"
- Options:
  - "Post all" — post every actionable finding
  - "Skip all" — post nothing, just keep the local report
  - "Let me pick" — user types comma-separated numbers (e.g. "1,3,5") in the freeform/Other field

---

## Step 5: Post Accepted Comments to PR

For each accepted finding, post an inline comment using `gh api`. Use the head SHA captured in Step 1.

```bash
gh api repos/{owner}/{repo}/pulls/{number}/comments \
  -f body="**[SEVERITY]** \`file:line\`

<finding description>

**Suggested fix:** <suggestion>

_Reviewed by Claude (functional-reviewer + code-quality-reviewer + adr-compliance-reviewer + performance-reviewer + data-side-effects-reviewer)_" \
  -f path="<file>" \
  -F line=<line> \
  -f commit_id="<head_sha>" \
  -f side="RIGHT"
```

If a line number doesn't map cleanly to the diff (the API returns an error), fall back to posting a general PR comment instead:

```bash
gh pr comment $ARGUMENTS --body "**[SEVERITY]** \`file:line\`

<finding description>

**Suggested fix:** <suggestion>

_Reviewed by Claude (functional-reviewer + code-quality-reviewer + adr-compliance-reviewer + performance-reviewer + data-side-effects-reviewer)_"
```

---

## Step 6: Cleanup

Checkout the original branch:

```bash
git checkout <ORIGINAL_BRANCH>
```

Print a summary: "Posted N comments to PR #$ARGUMENTS. Skipped M findings. Reported K informational (MEDIUM/LOW) findings locally."
