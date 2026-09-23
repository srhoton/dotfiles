# `~/.claude/bin`

Helper executables on `PATH` for Claude Code workflows.

## Tracked (shell scripts)

- `agent-msg` — inter-Claude mailbox CLI (legacy filesystem mailbox).
- `fb-repo-sync` — clones or fast-forwards the fullbay `act-/ath-/usr-/mig-/wor-/fin-/prt-/aps-/unt-/app-` repos, plus `fb-architecture/architecture-*` and `fb-peo-apex/apex`, into `~/git` on each repo's own default branch, without ever switching branches or touching a working tree (`-n` dry run, `-a` include archived).
- `mig-entity-status` — for a migration entity id or `act_…` account id plus an SSO profile (required, never defaulted), prints the entity ↔ account ↔ tenant mapping, the transform and migration Step Function runs in the last N days (cross-checked against the real execution status to catch stale table rows), and the latest transform and migration statistics, including the financials counts that exist only in the execution output. Read-only; a `uv` inline script, so it doesn't depend on which python is on `PATH` (`--days N`, `--mappings` per-type mapping counts, `--json`, `--region`).
- `pr-fix-queue` — finds **my own** open PRs that are blocked (changes requested, a merge conflict, an unresolved human review thread I haven't answered, or a human conversation comment I haven't marked handled with a 🚀 reaction) and starts a Claude session running `/fixit <PR#>` for each, in a worktree under `~/git/.pr-fix/` on a private `pr-fix/<PR#>` branch and its own tmux window. The session fixes, tests, commits, pushes and replies. Relaunch is gated on a fingerprint of the blocking input, not the head SHA, because its own push moves that SHA (`-n` dry run, `-f` force, `-m N` cap (default 2), `-o ORG` filter, `--include-bots` (threads only), `--retry OWNER/REPO#N` to unstick one PR, `--clean`). To dismiss a conversation comment without a session ("LGTM", thanks), add a 🚀 to it; no other reaction and no reply of mine counts. Classifier tests: `bin/tests/pr-fix-queue-classify.sh`.
- `pr-review-queue` — finds open PRs awaiting my review and starts a Claude session running `/reviewit <PR#>` for each, in a throwaway detached worktree under `~/git/.pr-review/` and its own tmux window (`-n` dry run, `-m N` cap, `-o ORG` filter, `--clean`).
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
