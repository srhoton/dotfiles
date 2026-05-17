#!/bin/bash
# dashboard.sh — single-render project dashboard for tmux pane.
# Invoked by `watch -tcn 10 dashboard.sh`. Prints once and exits.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/dashboard-data"
mkdir -p "$CACHE_DIR"
MCP_CACHE="$CACHE_DIR/mcp-status"

# Kick off the MCP cache refresher in the background if not already running.
if ! pgrep -f "dashboard-mcp-refresh.sh" >/dev/null 2>&1; then
  nohup "$SCRIPT_DIR/dashboard-mcp-refresh.sh" >/dev/null 2>&1 &
fi

# Color codes (tput returns empty strings in non-color terminals).
BOLD=$(tput bold 2>/dev/null || true)
DIM=$(tput dim 2>/dev/null || true)
RESET=$(tput sgr0 2>/dev/null || true)
CYAN=$(tput setaf 6 2>/dev/null || true)

proj=$(basename "$PWD")
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "no-git")
ahead="?"; behind="?"; staged=0; unstaged=0; untracked=0; shortstat=""
if [ "$branch" != "no-git" ]; then
  ahead=$(git rev-list --count "@{u}..HEAD" 2>/dev/null || echo "?")
  behind=$(git rev-list --count "HEAD..@{u}" 2>/dev/null || echo "?")
  staged=$(git diff --name-only --cached 2>/dev/null | wc -l | tr -d ' ')
  unstaged=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
  untracked=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
  # Combined diff stats: working tree + staged
  shortstat=$(git diff HEAD --shortstat 2>/dev/null | sed 's/^ //')
fi

printf "${BOLD}─────────────────────────────────────${RESET}\n"
printf " ${BOLD}Dashboard — %s${RESET}\n" "$proj"
printf " ${CYAN}%s${RESET} (↑%s ↓%s)\n" "$branch" "$ahead" "$behind"
printf "${BOLD}─────────────────────────────────────${RESET}\n"
printf " ${BOLD}GIT${RESET}\n"
printf "   Staged:    %s\n" "$staged"
printf "   Unstaged:  %s\n" "$unstaged"
printf "   Untracked: %s\n" "$untracked"
if [ -n "$shortstat" ]; then
  printf "   Diff:      ${DIM}%s${RESET}\n" "$shortstat"
fi
printf "\n"

printf " ${BOLD}RECENT FILES${RESET}\n"
git ls-files -mo --exclude-standard 2>/dev/null \
  | while read -r f; do [ -f "$f" ] && stat -f "%m %N" "$f"; done \
  | sort -rn | head -5 \
  | awk -v now="$(date +%s)" '{ ago=now-$1; mins=int(ago/60); if (mins<60) printf "   %-30s %dm\n", $2, mins; else printf "   %-30s %dh\n", $2, int(mins/60); }'
printf "\n"

printf " ${BOLD}RECENT COMMITS${RESET}\n"
git log --pretty=format:'   %h  %s  %ar' -3 2>/dev/null | sed 's/ ago//' | cut -c1-37
printf "\n${BOLD}─────────────────────────────────────${RESET}\n"

printf " ${BOLD}MCP${RESET}"
if [ -f "$MCP_CACHE" ]; then
  printf " — %s\n" "$(head -1 "$MCP_CACHE")"
  # Show only non-connected servers (auth-needed or failed). Connected count is in the summary.
  problems=$(tail -n +2 "$MCP_CACHE" | grep -E ' (!|✗)$' || true)
  if [ -n "$problems" ]; then
    echo "$problems"
  else
    printf "   ${DIM}all servers healthy${RESET}\n"
  fi
else
  printf "\n   ${DIM}(refreshing...)${RESET}\n"
fi
printf "${BOLD}─────────────────────────────────────${RESET}\n"

printf " ${BOLD}PRs (current branch)${RESET}\n"
if command -v gh >/dev/null 2>&1 && [ "$branch" != "no-git" ]; then
  pr_json=$(gh pr list --head "$branch" --json number,state,reviewDecision --limit 3 2>/dev/null || echo "[]")
  if [ "$pr_json" = "[]" ] || [ -z "$pr_json" ]; then
    printf "   ${DIM}(no PRs)${RESET}\n"
  else
    echo "$pr_json" | jq -r '.[] | "   #\(.number)  \(.state)  \(.reviewDecision // "-")"' 2>/dev/null
  fi
fi
