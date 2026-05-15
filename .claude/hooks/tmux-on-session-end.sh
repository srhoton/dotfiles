#!/bin/bash
# SessionEnd hook: clear pane title when Claude exits.
[ -z "$TMUX" ] && exit 0
tmux select-pane -T "" 2>/dev/null
exit 0
