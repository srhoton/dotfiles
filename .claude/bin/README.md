# `~/.claude/bin`

Helper executables on `PATH` for Claude Code workflows.

## Tracked (shell scripts)

- `agent-msg` — inter-Claude mailbox CLI (legacy filesystem mailbox).
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
