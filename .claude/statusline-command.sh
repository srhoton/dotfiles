#!/usr/bin/env bash
# Claude Code status line script
# Mirrors a Starship-style prompt with Claude Code context info

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
model=$(echo "$input" | jq -r '.model.display_name // ""')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

user=$(whoami)
host=$(hostname -s)

# Shorten home directory to ~
home="$HOME"
short_cwd="${cwd/#$home/\~}"

# Build context usage string
if [ -n "$used" ]; then
    ctx_str=" ctx:${used}%"
else
    ctx_str=""
fi

# Build model string
if [ -n "$model" ]; then
    model_str=" | ${model}"
else
    model_str=""
fi

# Python version (major.minor only)
py_ver=""
if command -v python3 &>/dev/null; then
    py_ver=$(python3 --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
elif command -v python &>/dev/null; then
    py_ver=$(python --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
fi
[ -n "$py_ver" ] && py_str=" py:${py_ver}" || py_str=""

# Java version (major.minor only)
java_str=""
if command -v java &>/dev/null; then
    java_raw=$(java -version 2>&1 | head -1 | grep -oE '"[0-9][^"]*"' | tr -d '"')
    if [ -n "$java_raw" ]; then
        # Handle both old (1.8.0_xxx -> 8) and new (17.0.x -> 17.0) versioning
        major=$(echo "$java_raw" | cut -d'.' -f1)
        minor=$(echo "$java_raw" | cut -d'.' -f2)
        if [ "$major" = "1" ]; then
            java_ver="${minor}"
        else
            java_ver="${major}.${minor}"
        fi
        java_str=" java:${java_ver}"
    fi
fi

# Node version (major.minor only)
node_str=""
if command -v node &>/dev/null; then
    node_ver=$(node --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
    [ -n "$node_ver" ] && node_str=" node:${node_ver}"
fi

# Combine version indicators
versions_str="${py_str}${java_str}${node_str}"

# Account indicator (set CLAUDE_ACCOUNT env var to "max" or "enterprise")
account="${CLAUDE_ACCOUNT:-}"
if [ -n "$account" ]; then
    account_str=" | ${account}"
else
    account_str=""
fi

printf "\033[32m%s@%s\033[0m \033[34m%s\033[0m\033[35m%s\033[0m\033[33m%s%s\033[0m\033[36m%s\033[0m" \
    "$user" "$host" "$short_cwd" "$account_str" "$model_str" "$ctx_str" "$versions_str"
