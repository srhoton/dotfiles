#!/usr/bin/env bash
#
# install-opencode.sh - link the generated opencode config into ~/.config/opencode.
#
# Symlinks AGENTS.md, opencode.json, agents/, commands/, rules/, skills/ and
# plugins/claude-hooks.js from this repo. Local files it does not own (config.json
# with a local provider, other plugins, node_modules) are left alone. Anything it
# would replace that is not already a link into this repo is moved aside to
# <name>.bak-<timestamp> first. Safe to re-run.
#
# A stale ~/.opencode (opencode does not read it as global config) is moved to
# ~/.opencode.bak-<timestamp>. Pass --keep-dot-opencode to leave it.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO/.config/opencode"
DEST="${OPENCODE_CONFIG_HOME:-$HOME/.config/opencode}"
STAMP="$(date +%Y%m%d%H%M%S)"
KEEP_DOT_OPENCODE=0

for arg in "$@"; do
  case "$arg" in
    --keep-dot-opencode) KEEP_DOT_OPENCODE=1 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

[ -f "$SRC/opencode.json" ] || { echo "missing $SRC/opencode.json; run scripts/claude-to-opencode first" >&2; exit 1; }

link() {
  local source="$1" target="$2"
  if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
    echo "ok       $target"
    return
  fi
  if [ -e "$target" ] || [ -L "$target" ]; then
    mv "$target" "$target.bak-$STAMP"
    echo "moved    $target -> $target.bak-$STAMP"
  fi
  ln -s "$source" "$target"
  echo "linked   $target -> $source"
}

mkdir -p "$DEST/plugins"
for name in AGENTS.md opencode.json agents commands rules skills; do
  link "$SRC/$name" "$DEST/$name"
done
link "$SRC/plugins/claude-hooks.js" "$DEST/plugins/claude-hooks.js"

if [ "$KEEP_DOT_OPENCODE" -eq 0 ] && [ -d "$HOME/.opencode" ] && [ ! -L "$HOME/.opencode" ]; then
  mv "$HOME/.opencode" "$HOME/.opencode.bak-$STAMP"
  echo "moved    $HOME/.opencode -> $HOME/.opencode.bak-$STAMP"
fi

for var in KAGI_API_KEY HARNESS_API_KEY HARNESS_BASE_URL HARNESS_TOOLSETS; do
  [ -n "${!var:-}" ] || echo "note     $var is not set; the MCP server that needs it will fail to start"
done
