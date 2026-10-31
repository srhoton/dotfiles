# `~/.claude/bin`

Helper executables on `PATH` for Claude Code workflows.

## Tracked (shell scripts)

- `adr-catalog` — loads the ADR catalog from `~/git/architecture-decisions` in one call, for the `adr-compliance-reviewer`.
  - Checks the repo exists and which branch it's on, and warns if it is behind `origin/master` or holds files that aren't named `*-ADR.md`.
  - For each ADR it prints the title, decision summary, ImplGuide `Applies to:` and Prohibited Patterns table, or `IMPLGUIDE MISSING`.
  - `--applies frontend|backend|infra|fullstack` filters, and lists the ADRs it excluded.
  - `--show <slug>` prints one ADR and its guide in full.
  - `--no-fetch`, `--root`. Read-only apart from `git fetch`.
- `ca-token` — fetches the CodeArtifact authorization token and caches it under `${XDG_CACHE_HOME:-~/.cache}/claude-bin/` (files 0600, dir 0700) until the earlier of 30 minutes before expiry and 11 hours.
  - Prints nothing secret by default. `eval "$(ca-token --env gradle|npm)"` puts the token in the environment (`ORG_GRADLE_PROJECT_codeartifactToken` / `AWS_CODEARTIFACT_TOKEN`); `--print` is the explicit opt-in; `--check` tests the cache without calling aws.
  - A failed fetch never falls back to a stale token: it prints `aws sso login --profile <P>` and exits 4 (3 = usage or no `aws`). `repo-gate` calls it for Gradle and Node repos that need it. Tests: `bin/tests/ca-token.sh`.
- `agent-msg` — inter-Claude mailbox CLI (legacy filesystem mailbox).
- `athena-q` — runs one Athena query: `--profile` and `--workgroup` are required and never defaulted; SQL comes from `-e`, `-f` or stdin.
  - Polls with 1-5s backoff and trusts a terminal state only when seen twice. Prints `athena-q: <state> qid= runtime= scanned= result=`, then up to `--max-rows` rows (table, `--tsv`, `--json`); `--out FILE` writes the full result and prints only the path and row count (slow above ~100k rows; use the S3 `result=` location for those).
  - Read-only by default: one SELECT/WITH/SHOW/DESCRIBE/EXPLAIN/VALUES statement; anything else needs `--allow-write`. It is a keyword guard, not a SQL parser.
  - Exit codes: 0 ok, 1 failed, 2 timed out (query stopped), 3 usage or guard refusal, 4 AWS error (prints the `aws sso login --profile` command). Tests: `bin/tests/athena-q.sh`.
- `cc-usage` — what Claude Code sessions cost, from the transcripts under `~/.claude/projects` (`--root`): main sessions, subagents (type from the sibling `agent-*.meta.json`) and workflow agents (`workflow:<label prefix>` from the workflow's `journal.jsonl`).
  - Each API response is counted once: a response is written as several JSONL lines that all repeat `usage`, so lines are deduplicated per transcript by `message.id` (else the line `uuid`), keeping the one with the largest `output_tokens`. Summing every line overcounts about 2.4×.
  - `--since 7d|Nh|YYYY-MM-DD` (default 7d), `--until`, `--by kind|agent|repo|session|day|model` (default kind; dates and days are UTC), `--agent TYPE`, `--repo SUBSTR`, `--top N` (default 15), `--json`.
  - Per group: cost, share, runs, responses, median and max responses per run, median and max peak context per run, cache-read $, cache-write $ (1h and 5m) and output $, then a TOTAL line. `<synthetic>` responses are ignored.
  - Prices are the list prices in the `PRICES` table at the top of the script (cache writes 2× input at 1h, 1.25× at 5m); update them when pricing changes. Read-only, standard library only. Tests: `bin/tests/cc-usage.sh`.
- `fanout-report` — turns a `review-fanout` workflow output file (the wrapped, bare, or embedded result) into a markdown report under `~/.claude/scratch/<repo>/`.
  - The report holds numbered actionable findings with verified yes/NO, refuted findings with their refutations, informational findings, and skipped reviewers.
  - Prints only the path and the counts (`--out`, `--stdout`, `--repo`).
- `fb-repo-sync` — clones or fast-forwards the fullbay `act-/ath-/usr-/mig-/wor-/fin-/prt-/aps-/unt-/app-/svo-/flt-` repos, plus `fb-architecture/architecture-*` and `fb-peo-apex/apex`, into `~/git` on each repo's own default branch, without ever switching branches or touching a working tree (`-n` dry run, `-a` include archived).
- `mig-entity-status` — for a migration entity id or `act_…` account id plus an SSO profile (required, never defaulted), prints the entity ↔ account ↔ tenant mapping, the transform and migration Step Function runs in the last N days (cross-checked against the real execution status to catch stale table rows), and the latest transform and migration statistics, including the financials counts that exist only in the execution output. Read-only; a `uv` inline script, so it doesn't depend on which python is on `PATH` (`--days N`, `--mappings` per-type mapping counts, `--json`, `--region`).
- `commit-notes` — `commit-notes -m MSGFILE [-n NOTESFILE] [--add PATH...] [--push] [-N]`: the `/trueup` commit, notes and push in one call.
  - Stages only the named paths (never `-A`, literal pathspecs), prints the staged stat, and refuses if nothing is staged or you are on the default branch.
  - Runs the Claude pre-commit and guard-pr-state hooks itself, then restores any staged content the hook changed outside `--add` (the formatter hooks run `git add -u`) and warns. Never skips hooks.
  - `--push` pushes (`-u origin HEAD` when the upstream isn't the same-named branch), prints `PR #N STATE base=BASE`, and warns on a merged or closed PR or a base that isn't the default branch. `-N` is a dry run. Tests: `bin/tests/commit-notes.sh`.
- `pr-fix-queue` — finds **my own** open PRs that are blocked (changes requested, a merge conflict, an unresolved human review thread I haven't answered, or a human conversation comment I haven't marked handled with a 🚀 reaction) and starts a Claude session running `/fixit <PR#>` for each, in a worktree under `~/git/.pr-fix/` on a private `pr-fix/<PR#>` branch and its own tmux window. The session fixes, tests, commits, pushes and replies. Relaunch is gated on a fingerprint of the blocking input, not the head SHA, because its own push moves that SHA (`-n` dry run, `-f` force, `-m N` cap (default 2), `-o ORG` filter, `--include-bots` (threads only), `--retry OWNER/REPO#N` to unstick one PR, `--clean`). To dismiss a conversation comment without a session ("LGTM", thanks), add a 🚀 to it; no other reaction and no reply of mine counts. Classifier tests: `bin/tests/pr-fix-queue-classify.sh`.
- `pr-my-turn` — lists **my own** open PRs that are waiting on me: merge conflicts, fixes I owe (changes requested, required checks failing, behind base, unanswered human review threads), and PRs ready to merge. Personal-repo PRs get their own self-merge section; everything else is counted in a "waiting on others" footer. Uses GitHub's `mergeStateStatus` rather than `reviewDecision`, since org rulesets can leave the latter empty while still requiring an approval. Read-only, standard-library Python (`-o ORG` filter, `--json`).
- `pr-ci-wait` — waits for a PR's checks.
  - Backoff runs from 30s to 2m, and a terminal state must be seen twice before it is trusted (flicker guard). Prints a line only when a check changes state.
  - On failure it prints the last 40 lines of each failed job's `gh run view --log-failed`.
  - Exit codes: 0 green, 1 failed or cancelled, 2 timed out (`--max-minutes`, default 30), 3 no checks reported, 4 `gh` kept failing.
- `pr-context` — everything about one PR in one call: header, head SHA vs local HEAD, mergeability, reviews, standing change requests, checks summary, files, and the **actionable** review threads and conversation comments (`--json`, `-R`).
  - "Actionable" uses the classifier in `lib/pr_feedback.py`, the same one `pr-fix-queue` uses, so `/fixit` and the queue agree.
  - `--body` adds the full PR description. `--diff [--only PATH]` adds the `gh pr diff` with new-file line numbers (the numbers `pr-review-post` accepts as inline anchors); if the diff can't be fetched, or the head moves while fetching, the report still prints with `diff_error` / `unavailable`.
  - Tests: `bin/tests/pr-context.sh`.
- `pr-stack` — `pr-stack [PR#...] [-R owner/repo] [--retarget] [--json]`: for stacked PRs (a child whose base branch is another PR's head branch), one line per PR with its state, base, head sha, parent PR and a verdict: `OK`, `NEEDS-RETARGET` (parent merged and its branch spent), `PARENT-CLOSED`, `NO-PARENT-PR`, `MERGED`, `CLOSED`.
  - The parent is the same-repo PR whose head is the base branch (open wins, else the most recently merged/closed; fork PRs are ignored). A merged parent only counts when its branch is gone from the remote or still at the merged head; a base that moved on, or that is a protected branch (e.g. `develop` right after a `develop -> main` release PR, when its tip still equals that PR's head), is live: `OK` with a note, never retargeted.
  - With no PR numbers it uses my open PRs. In a clone of the repo it also shows the head's ahead/behind vs `origin/<default>` after `git fetch -q origin` (a failed fetch or missing git warns and skips it).
  - Read-only unless `--retarget`, which runs `gh pr edit N --base <parent's base>` for each NEEDS-RETARGET PR (A <- B <- C with B merged into open A moves C onto A; it walks up past merged, spent parents and stops at the default branch; it does not rebase). Each PR is re-read just before its edit and skipped if it changed; a failed edit sets that PR's `retargetError`, the rest are still processed and the report/JSON is still printed.
  - Exit codes: 0 fine, 1 PR not found, 2 usage, gh failure, unexpected gh response or failed retarget, 3 a PR needs attention (NEEDS-RETARGET without `--retarget`, PARENT-CLOSED, NO-PARENT-PR). Tests: `bin/tests/pr-stack.sh`.
- `pr-approve` — `pr-approve <PR#> --sha <reviewed-sha> [-R owner/repo] [--body-file F] [-n]`: approves a PR after a clean `/reviewit`, but only if its head still starts with the reviewed SHA.
  - Refuses (exit 3) when the PR is not open, is a draft, is authored by the viewer, or the head moved since the review (prints both SHAs).
  - Otherwise POSTs the approval to `repos/{o}/{r}/pulls/N/reviews` with `commit_id` pinned to the head it verified (`gh pr review --approve` cannot pin a commit; default body names the reviewed SHA; sent in a payload file, never as an argument), then re-reads and prints the viewer's latest review id, state and commit. `-n` is a dry run.
  - GitHub does not reject a stale pinned commit (no 422), so the PR head is read again after the POST: if it moved, the approval is recorded on the old head and it warns (on repos without "dismiss stale approvals" that approval may still count toward merging) and exits 3. If GitHub rejects the pinned commit outright (422) nothing is approved: exit 3 with the API message. If the re-read shows an approval on another commit (should not happen), exit 3: an approval exists, dismiss it manually. If the approval went through but the re-read fails: exit 2, "approved, but ...", verify by hand.
  - Exit codes: 0 approved, 1 PR not found, 2 usage or gh failure, 3 refused. Tests: `bin/tests/pr-approve.sh`.
- `pr-review-post` — posts review findings from a JSON file, using the `/reviewit` comment format. Its patch splitter lives in `lib/numbered_diff.py`.
  - Findings on commentable diff lines go out as **one** PR review; the rest go into one conversation comment, so nothing is lost.
  - If the review POST fails, it retries with every finding in the fallback comment.
  - `-n` is a dry run; `--event`, `--body-file`. Bodies are always sent through files, never `@path`.
- `pr-review-queue` — finds open PRs awaiting my review and starts a Claude session running `/reviewit <PR#>` for each, in a throwaway detached worktree under `~/git/.pr-review/` and its own tmux window (`-n` dry run, `-m N` cap, `-o ORG` filter, `--clean`).
- `repo-gate` — detects the project type (Node, Gradle, Go, Python, Terraform) and runs its gates.
  - Gates: install (frozen only), typecheck, lint (`vet-diff` for Node), and the full test suite.
  - Prints one `PASS`/`FAIL`/`SKIPPED` line per gate with a short excerpt on failure, and ends `REPO-GATE: PASS|FAIL`; a PASS lists any skipped core gates as `PASS (skipped: …)`. Exit 0 or 1, and 2 when there's no project.
  - A stale `.terraform` is re-initialised with `-backend=false`, or reported SKIPPED with `--no-install`.
  - `--changed` runs only the related tests; `--json`, `-C`.
  - Gradle and Node repos that need a CodeArtifact token get one from `ca-token` automatically when it isn't already set (Node only when an install will run).
- `review-context` — reviewer orientation.
  - Prints the base branch (preferring `origin/<default>`), merge base, commits, diff stat and uncommitted changes, then `~/.claude/knowledge/defect-classes.md`.
  - `--files-only` prints just the deduplicated changed-file list for the review workflow: branch diff, staged, unstaged and untracked, with deleted files left out.
  - `--diff [-U N] [FILE...]` prints only a numbered diff (merge base to working tree, untracked files as all-added) as `<new-file line>| +added`, so reviewers don't need `git diff` plus `grep -n`. A path that isn't changed exits 3.
  - `--base`, `--no-defects`, `-C`.
- `sha-relation` — classifies a deployed SHA as ahead/behind/equal for env-drift checks.
- `stale-prs` — lists open PRs being ignored in the current repo.

## Not tracked (compiled binary)

- `micro-status-mcp` — the inter-agent mailbox MCP server. It is a large,
  architecture-specific Go binary, so it is **git-ignored** rather than
  committed. Build and install it from source:

  ```bash
  cd ~/git/micro-status-mcp
  make build
  cp -p bin/micro-status-mcp ~/.claude/bin/micro-status-mcp
  # restart the server pane: micro-status-mcp serve
  ```

  Source repo: `github.com/srhoton/micro-status-mcp`.
