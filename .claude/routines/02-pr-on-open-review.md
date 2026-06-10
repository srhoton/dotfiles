# Routine 2 — PR-on-Open Auto-Review

**Trigger:** GitHub webhooks — `pull_request.opened` AND `pull_request.ready_for_review` on user's repos. The routine self-filters drafts.

**Cloud MCPs used:**
- `claude.ai Slack` — summary output

**Secrets:**
- `GITHUB_TOKEN` — `repo` scope; used by WebFetch to read PR data and post inline comments

## Behavior

1. Webhook payload provides repo + PR number.
2. Routine fetches PR metadata and exits silently if `draft == true`.
3. For non-draft PRs, fetches the diff and runs a `/reviewit`-equivalent review pass.
4. Posts inline comments for CRITICAL/HIGH findings only.
5. Posts a Slack DM summary.

## Routine prompt

```
You are an auto-PR-reviewer. Triggered on pull_request.opened OR pull_request.ready_for_review webhook from GitHub.

Steps:
1. From the webhook payload, extract: repo (owner/name), PR number, head SHA.

2. WebFetch the PR metadata:
   GET https://api.github.com/repos/{owner}/{repo}/pulls/{N}
   Headers: Authorization: Bearer $GITHUB_TOKEN, Accept: application/vnd.github+json

3. DRAFT FILTER: if response.draft == true, EXIT SILENTLY. The routine re-fires on the ready_for_review event.

4. WebFetch the PR's changed files:
   GET https://api.github.com/repos/{owner}/{repo}/pulls/{N}/files

5. For each changed file (excluding test/, docs/, .github/, *.md), WebFetch its content at the head SHA:
   GET https://api.github.com/repos/{owner}/{repo}/contents/{path}?ref={head_sha}

6. Review the diff against the PR title and body for:

   FUNCTIONAL: does the diff do what the title/body says? Look for missing pieces called out in the description.

   QUALITY: hardcoded secrets, missing error handling on external/network/database calls, unbounded loops, eval/exec/dangerouslySetInnerHTML, SQL injection vectors, missing input validation.

   ADR: WebFetch https://api.github.com/repos/fullbay/architecture-decisions/contents/adrs and https://api.github.com/repos/fullbay/architecture-decisions/contents/implGuides. For each changed file, check the matching ImplGuide's "Prohibited Patterns" table for regex/pattern matches in the diff.

   For each finding, assign severity: CRITICAL (security/correctness bug), HIGH (ADR violation or clear quality issue), MEDIUM (best-practice deviation), LOW (style nit).

7. For each finding with severity CRITICAL or HIGH (cap at 15 total), post an inline comment:
   POST /repos/{owner}/{repo}/pulls/{N}/comments
   Body: {
     "body": "**[<SEVERITY>]** <one-line description>\n\n**Suggested fix:** <one-line>\n\n_Auto-review by Claude_",
     "commit_id": "<head_sha>",
     "path": "<file>",
     "line": <line>,
     "side": "RIGHT"
   }

8. Post a single Slack DM summary:
   "Auto-reviewed PR #{N} in {repo}: {critical_count} CRITICAL, {high_count} HIGH posted. {medium_low_count} informational findings not posted. <link to PR>"

Constraints:
- Cap at 15 inline comments to avoid review spam. If more, post top 15 by severity, mention overflow count in Slack summary.
- Skip test/, docs/, .github/, and *.md files entirely.
- If GITHUB_TOKEN is rate-limited (429), exit cleanly and let the next webhook re-trigger.
- Comment bodies are one-liners. No multi-paragraph essays.
```
