#!/bin/bash
# Notification hook: alert when Claude is waiting for the user.
[ -z "$TMUX" ] && exit 0

PROJECT=$(basename "$PWD")
INPUT=$(cat 2>/dev/null)
MSG=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('message','needs input'))" 2>/dev/null)
[ -z "$MSG" ] && MSG="needs input"

tmux display-message -d 5000 "⏸ Claude: $MSG — $PROJECT" 2>/dev/null
tmux select-pane -T "⏸ claude: $PROJECT" 2>/dev/null
printf '\a' >&2
exit 0
