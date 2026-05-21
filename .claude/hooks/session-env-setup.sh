#!/bin/bash
#
# session-env-setup.sh - SessionStart hook for Claude Code
#
# Writes environment variables into CLAUDE_ENV_FILE so they persist
# across all Bash tool calls in the session.
#

# ---------------------------------------------------------------------------
# 0. tmux pane title — show this is a Claude pane and which project.
#    Runs regardless of CLAUDE_ENV_FILE state so tmux integration is robust.
# ---------------------------------------------------------------------------
if [ -n "$TMUX" ]; then
  PROJECT=$(basename "$PWD")
  tmux select-pane -T "● claude: $PROJECT" 2>/dev/null
  tmux set -g pane-border-status top 2>/dev/null
  tmux set -g pane-border-format "#{pane_index}: #{pane_title}" 2>/dev/null
fi

# Register this pane in the agent mailbox so other Claude sessions can
# tmux-send-keys notifications here. No-op outside tmux.
if [ -n "$TMUX" ] && [ -x "$HOME/.claude/bin/agent-msg" ]; then
  "$HOME/.claude/bin/agent-msg" register >/dev/null 2>&1 || true
fi

[ -z "$CLAUDE_ENV_FILE" ] && exit 0

# ---------------------------------------------------------------------------
# 1. Homebrew shell environment (PATH, HOMEBREW_PREFIX, etc.)
#    Write only simple export lines — CLAUDE_ENV_FILE doesn't support eval.
# ---------------------------------------------------------------------------
if [ -x /opt/homebrew/bin/brew ]; then
  cat >> "$CLAUDE_ENV_FILE" <<'BREW'
export HOMEBREW_PREFIX="/opt/homebrew"
export HOMEBREW_CELLAR="/opt/homebrew/Cellar"
export HOMEBREW_REPOSITORY="/opt/homebrew"
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
export MANPATH="/opt/homebrew/share/man:${MANPATH:-}"
export INFOPATH="/opt/homebrew/share/info:${INFOPATH:-}"
BREW
fi

# ---------------------------------------------------------------------------
# 2. Additional PATH entries (from ~/.bashrc)
# ---------------------------------------------------------------------------
cat >> "$CLAUDE_ENV_FILE" <<'PATHS'
export PATH="/opt/homebrew/opt/mysql@8.4/bin:$PATH"
export PATH="$PATH:/opt/homebrew/opt/python@3.11/libexec/bin"
export PATH="$PATH:$HOME/go/bin"
export PATH="$PATH:$HOME/.local/bin"
PATHS

# ---------------------------------------------------------------------------
# 3. Claude account type indicator for statusline
#    Set CLAUDE_ACCOUNT in your shell profile to override:
#      export CLAUDE_ACCOUNT="enterprise"  (or "max")
# ---------------------------------------------------------------------------
if [ -n "$CLAUDE_ACCOUNT" ]; then
  echo "export CLAUDE_ACCOUNT=\"$CLAUDE_ACCOUNT\"" >> "$CLAUDE_ENV_FILE"
fi

exit 0
