You are unblocking **my own** PR #$ARGUMENTS. Its reviewers asked for changes, left unresolved comments, or it has a merge conflict. Your job is to resolve the conflict, address every actionable comment, push, and reply on each thread.

**IMPORTANT: Use `gh` CLI for ALL GitHub operations. Do NOT use GitHub MCP tools.**

This command is usually launched by `~/.claude/bin/pr-fix-queue` inside a prepared worktree, but it must also work when run by hand in an ordinary clone. Step 1 tells the two apart.

Follow these steps exactly.

---

## Step 1: Orient

```bash
REPO=$(gh repo view --json owner,name --jq '.owner.login + "/" + .name')
gh pr view $ARGUMENTS --json number,title,state,mergeable,reviewDecision,headRefName,baseRefName,headRefOid,url
git branch --show-current
git status --porcelain
```

Save `headRefName`, `baseRefName` and `state`. Then check three things and **stop and report** rather than guessing if any is wrong:

- `state` must be `OPEN`. A merged or closed PR is not to be touched.
- You must be on the PR's code. A `pr-fix/<N>` branch (created by `pr-fix-queue`, tracking `origin/<headRefName>`) counts — so does the real head branch. If you are on neither, run `gh pr checkout $ARGUMENTS`, but only when the working tree is clean; if it is dirty with unrelated changes, stop.
- If `git status --porcelain` shows pre-existing uncommitted changes, they are **mine and deliberate**. Preserve them. Do not stash, revert, or commit them as part of your work unless they are plainly part of the fix.

If `git log @{u}..HEAD` is non-empty there are already-committed, unpushed commits on this branch. Inspect them — they are part of the PR and your eventual push will include them. Say so in your final report.

---

## Step 2: Gather the actionable feedback

Get the unresolved threads with their file, line, body and the numeric comment id needed to reply:

```bash
gh api graphql -f query='
query($owner:String!, $name:String!, $num:Int!) {
  repository(owner:$owner, name:$name) {
    pullRequest(number:$num) {
      reviewThreads(first: 60) {
        nodes {
          id isResolved isOutdated path line
          comments(first: 30) {
            nodes { databaseId body createdAt author { login __typename } }
          }
        }
      }
    }
  }
}' -f owner="${REPO%/*}" -f name="${REPO#*/}" -F num=$ARGUMENTS
```

A thread is **actionable** when all of these hold — this is the same test `pr-fix-queue` uses, so matching it is what stops the PR from being re-queued:

- `isResolved` is false and `isOutdated` is false
- its **first** comment's author is a human (`__typename == "User"`)
- its **last** comment is not mine (if I already replied, it is waiting on the reviewer, not on me)

Also read the review bodies for context, since a `CHANGES_REQUESTED` review often explains itself outside any thread:

```bash
gh pr view $ARGUMENTS --json reviews --jq '.reviews[] | select(.state=="CHANGES_REQUESTED") | {author: .author.login, body: .body}'
```

List what you found before changing anything: each actionable thread as `path:line — reviewer — the ask`, plus the conflict state. If there is nothing actionable and no conflict, say so and stop.

---

## Step 3: Resolve the merge conflict (only if `mergeable == "CONFLICTING"`)

**Merge. Never rebase, never force-push** — this branch is published and a rewrite can destroy a collaborator's work.

```bash
git fetch origin <baseRefName>
git merge "origin/<baseRefName>"
```

Resolve each conflict on its merits: read both sides and understand what each change was for. Do not resolve by blanket "take ours" or "take theirs". If a conflict needs a judgement call you cannot make from the code — two deliberate changes to the same logic — stop and report it rather than guessing.

After resolving, `git merge --continue` (or commit the merge), then re-run the build before moving on. A conflict resolution that compiles is not necessarily correct; check that both intents survive.

---

## Step 4: Address the comments

Apply CLAUDE.md **Fix Discipline** to every actionable thread:

- **Verify the claim first.** Read the code the comment points at. If the comment is wrong, do not change the code — refute it with evidence (a `file:line`, a test result, a query result) and reply saying so. Refuting a reviewer with evidence is a correct outcome.
- **Class, not site.** Before fixing a defect at the one line a reviewer noticed, grep or use the LSP to find its siblings, then fix or explicitly clear each. Report the enumeration.
- **One minimal fix per defect.** Do not ship a second fix for the same problem without showing the first is insufficient.
- **Never trade loud for silent.** A fix must not turn a detectable failure into a quietly swallowed one.

Follow the repo's own conventions and the language rules in CLAUDE.md. If a comment asks for something you believe is wrong for the codebase, say so in the reply rather than silently complying or silently ignoring it.

---

## Step 5: Verify

Run the full test suite, plus the language gate from CLAUDE.md:

- Java/Quarkus: `./gradlew spotlessApply` then the full `./gradlew build`
- TypeScript: the project's `typecheck`/`build` script, and `tsc --noEmit` must pass
- Python: the project's test + lint entry points (`uv run` based)
- Terraform: `terraform fmt`, `terraform validate`

**Do not push a red build.** If a test fails and it is unrelated to your change, that is still yours to deal with — fix it or report precisely why it cannot be fixed here. Do not bypass hooks with `--no-verify`.

---

## Step 6: Commit and push

Write the commit message to a tempfile and use `git commit -F` (never a `-m` heredoc — backticks corrupt it):

```bash
git add <specific files>
git diff --cached --stat     # confirm the intended files are actually staged
git commit -F /tmp/fixit-msg.txt
```

The message should say what the reviewers asked for and what you changed, not "address review comments".

Then re-check the PR is still open, and push with an **explicit refspec**:

```bash
gh pr view $ARGUMENTS --json state -q .state    # must still be OPEN
git push origin "HEAD:refs/heads/<headRefName>"
```

The explicit refspec is required, not stylistic: in a `pr-fix-queue` worktree the local branch is `pr-fix/<N>` while the remote branch is `<headRefName>`, `push.default` is `simple` on this machine, and the queue additionally sets `push.default=nothing` in the worktree so that no bare `git push` can fire by accident.

Push rules:

- **Never** `--force`. **Never** `--force-with-lease`.
- Rejected as non-fast-forward (someone else pushed): `git fetch origin <headRefName> && git merge FETCH_HEAD`, resolve, re-run tests, then retry the push **once**. If it is rejected again, stop and report.
- Rejected by branch protection: stop and report. Do not try to work around it.

---

## Step 7: Reply on every thread

Reply **in-thread** using the replies endpoint and the `databaseId` of the thread's first comment from Step 2:

```bash
gh api --method POST \
  "repos/$REPO/pulls/$ARGUMENTS/comments/<databaseId>/replies" \
  -f body="<your reply>"
```

Fall back to `gh pr comment $ARGUMENTS --body "..."` only if the threaded reply fails, and say that you fell back.

Every actionable thread gets a reply — fixed, or refuted with the evidence, or deferred with the reason. This is not optional: the reply is what marks the thread as waiting on the reviewer instead of on me, and `pr-fix-queue` uses exactly that signal to stop re-queueing this PR. A fixed-but-unanswered thread will be picked up again on the next run.

Do **not** resolve the threads. Resolving is the reviewer's call.

---

## Step 8: Report

Close with a compact summary:

- conflict: resolved (merge commit SHA) / none / could not resolve + why
- per thread: `path:line` — fixed / refuted (with the evidence) / deferred (with the reason)
- tests: what you ran and the result
- the pushed SHA and the PR url
- anything left for me to decide

Keep it to the table plus a short note, per CLAUDE.md output discipline. If any step stopped early, lead with that — do not bury a blocker under a list of successes.
