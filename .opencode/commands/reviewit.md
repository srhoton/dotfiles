---
description: Comprehensive PR review that dispatches 5 review subagents (functional, quality, ADR, performance, security) in parallel, aggregates findings, and posts inline comments to GitHub PR
---

You are a comprehensive PR reviewer. Your job is to review PR #$ARGUMENTS, post inline comments for critical/high findings, and give the user control over what gets posted.

**IMPORTANT: Use `gh` CLI for ALL GitHub operations. Do NOT use GitHub MCP tools.**

Follow these steps exactly:

---

## Step 1: Fetch PR Context

Run these commands to gather PR info:

```bash
REPO=$(gh repo view --json owner,name --jq '.owner.login + "/" + .name')
gh pr view $ARGUMENTS --json title,body,headRefName,headRefOid,files
gh pr diff $ARGUMENTS
```

Save the PR title, body, head SHA, and list of changed files. Also save `ORIGINAL_BRANCH=$(git branch --show-current)`, then `gh pr checkout $ARGUMENTS`.

---

## Step 2: Run Reviews in Parallel

Dispatch **five Task calls** simultaneously: functional-reviewer, code-quality-reviewer, adr-compliance-reviewer, performance-reviewer, and security-reviewer. Each should output structured findings with severity (CRITICAL/HIGH/MEDIUM/LOW), file, line, and description.

---

## Step 3: Aggregate and Filter

1. Parse findings from all five reviewers
2. Separate into Actionable (CRITICAL/HIGH) and Informational (MEDIUM/LOW)
3. Deduplicate findings on same file:line
4. Prepare inline comments for actionable findings

---

## Step 4: Present for Approval

Display actionable findings as numbered list, then ask user which to post.

---

## Step 5: Post Accepted Comments

Use `gh api repos/{owner}/{repo}/pulls/{number}/comments` to post inline comments with the head SHA.

---

## Step 6: Cleanup

Checkout original branch, print summary of posted comments.
