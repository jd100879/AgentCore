#!/usr/bin/env bash
# Setup Grok as a custom MCP server for Claude Code
# This must be run OUTSIDE of Claude Code sessions

set -e

PROJECT_ROOT="/Users/james/Projects/AgentCore"
STORAGE_STATE="$PROJECT_ROOT/.browser-profiles/grok-state.json"
START_URL="https://x.com/i/grok"

echo "🔧 Setting up Grok MCP server..."

# Check if storage state exists
if [ ! -f "$STORAGE_STATE" ]; then
    echo "❌ Storage state not found: $STORAGE_STATE"
    echo "Run: node scripts/init-grok-storage-state.mjs"
    exit 1
fi

echo "✓ Storage state exists"

# Add the MCP server
echo "Adding playwright-grok MCP server..."
claude mcp add --scope local playwright-grok -- \
    npx -y @playwright/mcp@latest --isolated \
    --storage-state "$STORAGE_STATE" \
    --start-url "$START_URL"

echo ""
echo "✅ Grok MCP server added successfully!"
echo ""
echo "Next steps:"
echo "1. Restart your Claude Code session"
echo "2. Tools will be available as: mcp__playwright-grok__browser_*"
echo ""
