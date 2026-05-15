#!/bin/bash
# Stop hook: notify the user via tmux when Claude finishes a turn.
[ -z "$TMUX" ] && exit 0

PROJECT=$(basename "$PWD")
tmux display-message "✓ Claude idle — $PROJECT" 2>/dev/null
tmux select-pane -T "✓ claude: $PROJECT" 2>/dev/null
printf '\a' >&2
exit 0
