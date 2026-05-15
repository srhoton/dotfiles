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

# Split right side (35% width) for logs/build
tmux split-window -h -p 35 -t "$SESSION:main" -c "$WORKDIR"

# Split right side bottom (50% of right column) for shell
tmux split-window -v -p 50 -t "$SESSION:main.1" -c "$WORKDIR"

# Set pane titles for clarity
tmux select-pane -t "$SESSION:main.0" -T "claude"
tmux select-pane -t "$SESSION:main.1" -T "logs/build"
tmux select-pane -t "$SESSION:main.2" -T "shell"

# Enable pane border titles for this session
tmux set-option -t "$SESSION" pane-border-status top
tmux set-option -t "$SESSION" pane-border-format " #{pane_title} "

# Start Claude in the main pane
tmux send-keys -t "$SESSION:main.0" "claude" C-m

# Focus the Claude pane
tmux select-pane -t "$SESSION:main.0"

# Attach
exec tmux attach -t "$SESSION"
