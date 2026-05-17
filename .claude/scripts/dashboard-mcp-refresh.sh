#!/bin/bash
# dashboard-mcp-refresh.sh — refresh MCP status cache every 60s.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/dashboard-data"
mkdir -p "$CACHE_DIR"
MCP_CACHE="$CACHE_DIR/mcp-status"
TMP="$MCP_CACHE.tmp.$$"

trap 'rm -f "$TMP"' EXIT

while true; do
  # Run `claude mcp list` and parse:
  #   line 1: summary "N connected, M auth, K failed"
  #   lines 2+: list of servers with ✓/!/✗ markers
  output=$(claude mcp list 2>&1 | grep -E '^\s*\S+.*-\s+(✓|!|✗)' || true)
  connected=$(echo "$output" | grep -c '✓' || echo 0)
  auth=$(echo "$output" | grep -c '!' || echo 0)
  failed=$(echo "$output" | grep -c '✗' || echo 0)
  {
    printf "%d connected, %d auth, %d failed\n" "$connected" "$auth" "$failed"
    echo "$output" \
      | sed -E 's/^\s*//; s/: .* - / /; s/✓ Connected.*/✓/; s/! Needs authentication.*/!/; s/✗ Failed.*/✗/' \
      | head -20 \
      | sed 's/^/   /'
  } > "$TMP"
  mv "$TMP" "$MCP_CACHE"
  sleep 60
done
