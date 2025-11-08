#!/bin/bash

set -e

echo "Running post-create setup..."

# Ensure uv is in PATH for the vscode user
if [ ! -f "$HOME/.cargo/env" ]; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi
source "$HOME/.cargo/env"

# Create Python virtual environment directory
mkdir -p "$HOME/.venvs"

# Configure git (if not already configured)
if [ -z "$(git config --global user.name)" ]; then
    echo "Git user.name not set. Please configure git with:"
    echo "  git config --global user.name 'Your Name'"
    echo "  git config --global user.email 'your.email@example.com'"
fi

# Set up Go workspace
mkdir -p "$HOME/go/src" "$HOME/go/bin" "$HOME/go/pkg"

# Configure Starship
if [ ! -f "$HOME/.config/starship.toml" ]; then
    mkdir -p "$HOME/.config"
    cat > "$HOME/.config/starship.toml" <<'EOF'
# Starship configuration
add_newline = true

[character]
success_symbol = "[➜](bold green)"
error_symbol = "[➜](bold red)"

[directory]
truncation_length = 3
truncate_to_repo = true

[git_branch]
symbol = "🌱 "

[git_status]
conflicted = "⚔️ "
ahead = "⇡${count}"
behind = "⇣${count}"
diverged = "⇕⇡${ahead_count}⇣${behind_count}"
untracked = "🤷"
stashed = "📦"
modified = "📝"
staged = '[++\($count\)](green)'
renamed = "👅"
deleted = "🗑"

[nodejs]
symbol = "⬢ "

[python]
symbol = "🐍 "

[golang]
symbol = "🐹 "

[java]
symbol = "☕ "

[aws]
symbol = "☁️ "
EOF
fi

# Add useful aliases to bashrc
cat >> "$HOME/.bashrc" <<'EOF'

# Custom aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'

# Python aliases
alias python=python3
alias venv='python -m venv'

# Git aliases
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'

# AWS CLI aliases
alias awswhoami='aws sts get-caller-identity'
EOF

echo "Post-create setup completed!"
echo ""
echo "Installed versions:"
echo "  Java: $(java -version 2>&1 | head -n 1)"
echo "  Python: $(python --version)"
echo "  Go: $(go version)"
echo "  Node: $(node --version)"
echo "  npm: $(npm --version)"
echo "  TypeScript: $(tsc --version)"
echo "  AWS CLI: $(aws --version)"
echo "  Starship: $(starship --version)"
echo "  uv: $(uv --version)"
echo ""
echo "Ready to develop!"
