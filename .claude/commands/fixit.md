You are unblocking **my own** PR #$ARGUMENTS. Its reviewers asked for changes, left unresolved review threads or conversation comments, or it has a merge conflict. Your job is to resolve the conflict, address every actionable thread and comment, push, reply, and mark each conversation comment handled.

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

Then get the **conversation comments** — top-level comments that are not attached to a line. Reviewers — including ones running `/reviewit`, which posts here when an inline comment is rejected — leave real findings here, and they have no thread:

```bash
ME=$(gh api user --jq .login)
gh api graphql -f query='
query($owner:String!, $name:String!, $num:Int!) {
  repository(owner:$owner, name:$name) {
    pullRequest(number:$num) {
      comments(last: 50) {
        totalCount
        nodes {
          databaseId url body createdAt lastEditedAt isMinimized
          author { login __typename }
          reactionGroups { content viewerHasReacted }
          reactions(last: 20) { nodes { content createdAt user { login } } }
        }
      }
    }
  }
}' -f owner="${REPO%/*}" -f name="${REPO#*/}" -F num=$ARGUMENTS
```

A conversation comment is **unhandled** when all of these hold — again the same test `pr-fix-queue` uses:

- its author is a human (`__typename == "User"`) and is not me, and `isMinimized` is false
- I do **not** have a `ROCKET` reaction on it that is at least as new as its `lastEditedAt` (a comment edited after my rocket is unhandled again). `reactionGroups` says whether my rocket exists; `reactions` gives its time. If my rocket exists but is not among the 20 reactions listed, treat the comment as handled.

Only my `ROCKET` counts. A thumbs-up of mine, or a reply of mine further down, does **not** make a comment handled.

An unhandled comment can still be **already replied**: an earlier run, my other machine, or I by hand answered it and only the rocket is missing. It counts as already replied **only** when a comment of mine both

- has a `createdAt` newer than the unhandled comment's `lastEditedAt` (or its `createdAt` if it was never edited), and
- contains `#issuecomment-<that comment's databaseId>` in its body.

A reply of mine that predates the comment's latest edit does not count: the reviewer changed the ask after I answered, so it needs fresh work and a fresh reply. Position in the conversation is never enough. An already-replied comment needs no Step 4 work — confirm the fix or refutation it describes is really there, then it only needs its rocket in Step 7.

Sort every other unhandled comment into one of two kinds:

- **actionable** — it asks for a change, reports a defect, or asks me a question
- **acknowledge-only** — it asks for nothing at all: "LGTM", thanks, a question addressed to someone else

When in doubt it is **actionable**. A comment that contains any finding is actionable even when it is wrapped in praise, marked MEDIUM/LOW/nit, or phrased as an observation — acknowledge-only comments get a rocket and no reply, so misfiling a finding there buries it.

Also read the review bodies for context, since a `CHANGES_REQUESTED` review often explains itself outside any thread:

```bash
gh pr view $ARGUMENTS --json reviews --jq '.reviews[] | select(.state=="CHANGES_REQUESTED") | {author: .author.login, body: .body}'
```

List what you found before changing anything: each actionable thread as `path:line — reviewer — the ask`, each unhandled conversation comment as `<comment url> — reviewer — the ask` (or `— acknowledge-only`), plus the conflict state. If `totalCount` is over 50, say that only the newest 50 comments were checked. If there is nothing actionable, nothing to acknowledge, nothing already replied and no conflict, say so and stop. If the only work is acknowledge-only or already-replied comments, skip Step 3 and Step 4 — but Step 5 and Step 6 still decide for themselves whether there is anything to verify and push.

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

Apply CLAUDE.md **Fix Discipline** to every actionable thread and every actionable conversation comment — a finding is the same finding wherever the reviewer typed it:

- **Verify the claim first.** Read the code the comment points at. If the comment is wrong, do not change the code — refute it with evidence (a `file:line`, a test result, a query result) and reply saying so. Refuting a reviewer with evidence is a correct outcome.
- **Class, not site.** Before fixing a defect at the one line a reviewer noticed, grep or use the LSP to find its siblings, then fix or explicitly clear each. Report the enumeration.
- **One minimal fix per defect.** Do not ship a second fix for the same problem without showing the first is insufficient.
- **Never trade loud for silent.** A fix must not turn a detectable failure into a quietly swallowed one.

Follow the repo's own conventions and the language rules in CLAUDE.md. If a comment asks for something you believe is wrong for the codebase, say so in the reply rather than silently complying or silently ignoring it.

---

## Step 5: Verify

First decide whether there is anything to verify and push. Check now, not from memory of Step 1:

```bash
git status --porcelain
git log --oneline @{u}..HEAD
```

Skip this step and Step 6 **only if both are empty** — every finding was refuted, or the comments were acknowledge-only or already replied. A merge commit from Step 3 leaves the tree clean but is still unpushed, and so are commits that already existed in Step 1: both have to be verified and pushed. Uncommitted changes that were already there in Step 1 are mine (see Step 1) and do not count as work to push.

Run the full test suite, plus the language gate from CLAUDE.md:

- Java/Quarkus: `./gradlew spotlessApply` then the full `./gradlew build`
- TypeScript: the project's `typecheck`/`build` script, and `tsc --noEmit` must pass
- Python: the project's test + lint entry points (`uv run` based)
- Terraform: `terraform fmt`, `terraform validate`

**Do not push a red build.** If a test fails and it is unrelated to your change, that is still yours to deal with — fix it or report precisely why it cannot be fixed here. Do not bypass hooks with `--no-verify`.

---

## Step 6: Commit and push

If you changed no files there is nothing to commit — do not make an empty commit — but still push when `git log @{u}..HEAD` is non-empty.

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

## Step 7: Reply on every thread, then reply to and mark every conversation comment

If Step 5 or Step 6 stopped you (red build, rejected push), do **not** reply and do **not** add any rocket — nothing has been delivered yet. Report instead.

### 7a. Review threads

Reply **in-thread** using the replies endpoint and the `databaseId` of the thread's first comment from Step 2:

```bash
gh api --method POST \
  "repos/$REPO/pulls/$ARGUMENTS/comments/<databaseId>/replies" \
  -f body="<your reply>"
```

Fall back to `gh pr comment $ARGUMENTS --body "..."` only if the threaded reply fails, and say that you fell back.

Every actionable thread gets a reply — fixed, or refuted with the evidence, or deferred with the reason. This is not optional: the reply is what marks the thread as waiting on the reviewer instead of on me, and `pr-fix-queue` uses exactly that signal to stop re-queueing this PR. A fixed-but-unanswered thread will be picked up again on the next run.

Do **not** resolve the threads. Resolving is the reviewer's call.

### 7b. Conversation comments

Conversation comments have no thread to reply in, so the "handled" signal is my `ROCKET` reaction, and `pr-fix-queue` keeps re-queueing this PR until every unhandled comment has one. **The order below is the safety property — reply first, rocket second.** A rocket with no reply would mark a finding handled that nobody answered; a reply with no rocket just gets this PR one more run, which adds the rocket.

1. **Re-fetch** the conversation comments (the Step 2 query). Another run — my other machine, or me by hand — may have replied while you worked. Apply Step 2's **already replied** test again, exactly as written there (a comment of mine newer than the comment's last edit that contains `#issuecomment-<its databaseId>`). Drop those from the reply you are about to write; they still get their rocket in 3. A comment whose `lastEditedAt` moved while you worked was changed under you: treat it as new, below. If the re-fetch shows a **new** unhandled comment you have not worked on, leave it alone: no reply, no rocket. Name it in the report; the queue will pick it up.
2. **Post one reply** covering every actionable comment that is not already replied. For each, give its full URL (the `url` field, which ends in `#issuecomment-<databaseId>` — the already-replied test depends on that exact form) and the outcome — fixed (with the commit SHA), refuted (with the evidence), or deferred (with the reason):

   ```bash
   gh pr comment $ARGUMENTS --body-file /tmp/fixit-reply.md
   ```

   Write the body to a file; never an inline heredoc with backticks. Skip this when there is nothing left to reply to. If the post fails, stop here and report — add no rockets.
3. **Only after the reply succeeded** (or was not needed), add the rocket to each comment you handled — the actionable ones you replied to, the already-replied ones, and the acknowledge-only ones:

   ```bash
   gh api --method POST "repos/$REPO/issues/comments/<databaseId>/reactions" -f content=rocket
   ```

   Check each call. If one fails, say so at the top of the report with the comment URL. Do not retry in a loop: the queue will launch one more run, which finds the reply already posted and only adds the missing rocket.

Acknowledge-only comments get the rocket and **no reply** — do not answer "LGTM" with a comment. Never add a rocket to a comment you did not read and deal with, and never to one you chose to defer without saying so in the reply.

---

## Step 8: Report

Close with a compact summary:

- conflict: resolved (merge commit SHA) / none / could not resolve + why
- per thread: `path:line` — fixed / refuted (with the evidence) / deferred (with the reason)
- per conversation comment: `<comment url>` — fixed / refuted / deferred / acknowledged / already replied, and whether its rocket was added
- any rocket that failed to post, and any new comment that arrived while you worked and was left for the next run
- tests: what you ran and the result
- the pushed SHA and the PR url
- anything left for me to decide

Keep it to the table plus a short note, per CLAUDE.md output discipline. If any step stopped early, lead with that — do not bury a blocker under a list of successes.
