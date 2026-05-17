#!/bin/bash
# claude-layout: create a tmux layout for a Claude work session.
# Usage:
#   claude-layout              # uses current directory's basename as session name
#   claude-layout my-project   # uses custom session name

set -e

PROJECT="${1:-$(basename "$PWD")}"
SESSION="claude-$PROJECT"
WORKDIR="$PWD"

# If session already exists, just attach
if tmux has-session -t "$SESSION" 2>/dev/null; then
  exec tmux attach -t "$SESSION"
fi

# Create new session with main Claude pane
tmux new-session -d -s "$SESSION" -c "$WORKDIR" -n main

# Split right side (35% width) for the dashboard (full height)
tmux split-window -h -p 35 -t "$SESSION:main" -c "$WORKDIR"

# Set pane titles for clarity
tmux select-pane -t "$SESSION:main.0" -T "claude"
tmux select-pane -t "$SESSION:main.1" -T "dashboard"

# Enable pane border titles for this session
tmux set-option -t "$SESSION" pane-border-status top
tmux set-option -t "$SESSION" pane-border-format " #{pane_title} "

# Start Claude in the main pane
tmux send-keys -t "$SESSION:main.0" "claude" C-m

# Launch the dashboard in the top-right pane (escape hatch: CLAUDE_LAYOUT_NO_DASHBOARD=1)
if [ -z "${CLAUDE_LAYOUT_NO_DASHBOARD:-}" ]; then
  tmux send-keys -t "$SESSION:main.1" "watch -tcn 10 $HOME/.claude/scripts/dashboard.sh" C-m
fi

# Focus the Claude pane
tmux select-pane -t "$SESSION:main.0"

# Attach
exec tmux attach -t "$SESSION"
