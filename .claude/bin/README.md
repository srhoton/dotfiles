# `~/.claude/bin`

Helper executables on `PATH` for Claude Code workflows.

## Tracked (shell scripts)

- `adr-catalog` — loads the ADR catalog from `~/git/architecture-decisions` in one call, for the `adr-compliance-reviewer`.
  - Checks the repo exists and which branch it's on, and warns if it is behind `origin/master` or holds files that aren't named `*-ADR.md`.
  - For each ADR it prints the title, decision summary, ImplGuide `Applies to:` and Prohibited Patterns table, or `IMPLGUIDE MISSING`.
  - `--applies frontend|backend|infra|fullstack` filters, and lists the ADRs it excluded.
  - `--show <slug>` prints one ADR and its guide in full.
  - `--no-fetch`, `--root`. Read-only apart from `git fetch`.
- `agent-msg` — inter-Claude mailbox CLI (legacy filesystem mailbox).
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
  - Tests: `bin/tests/pr-context.sh`.
- `pr-review-post` — posts review findings from a JSON file, using the `/reviewit` comment format.
  - Findings on commentable diff lines go out as **one** PR review; the rest go into one conversation comment, so nothing is lost.
  - If the review POST fails, it retries with every finding in the fallback comment.
  - `-n` is a dry run; `--event`, `--body-file`. Bodies are always sent through files, never `@path`.
- `pr-review-queue` — finds open PRs awaiting my review and starts a Claude session running `/reviewit <PR#>` for each, in a throwaway detached worktree under `~/git/.pr-review/` and its own tmux window (`-n` dry run, `-m N` cap, `-o ORG` filter, `--clean`).
- `repo-gate` — detects the project type (Node, Gradle, Go, Python, Terraform) and runs its gates.
  - Gates: install (frozen only), typecheck, lint (`vet-diff` for Node), and the full test suite.
  - Prints one `PASS`/`FAIL`/`SKIPPED` line per gate with a short excerpt on failure, and ends `REPO-GATE: PASS|FAIL`; a PASS lists any skipped core gates as `PASS (skipped: …)`. Exit 0 or 1, and 2 when there's no project.
  - A stale `.terraform` is re-initialised with `-backend=false`, or reported SKIPPED with `--no-install`.
  - `--changed` runs only the related tests; `--json`, `-C`.
- `review-context` — reviewer orientation.
  - Prints the base branch (preferring `origin/<default>`), merge base, commits, diff stat and uncommitted changes, then `~/.claude/knowledge/defect-classes.md`.
  - `--files-only` prints just the deduplicated changed-file list for the review workflow: branch diff, staged, unstaged and untracked, with deleted files left out.
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
