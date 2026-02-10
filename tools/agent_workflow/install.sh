#!/bin/bash
# Install agent workflow tools to system PATH
# Core multi-agent coordination and automation scripts

set -euo pipefail

INSTALL_DIR="${HOME}/.local/bin"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${HOME}/.local/lib/agent_workflow"

echo "Installing agent workflow tools..."
echo ""

# Create directories
mkdir -p "$INSTALL_DIR"
mkdir -p "$LIB_DIR"

# Copy lib files first (dependencies)
if [ -d "$SOURCE_DIR/lib" ]; then
    cp -r "$SOURCE_DIR/lib/"* "$LIB_DIR/"
    echo "✓ Installed library files to $LIB_DIR"
fi

# Core workflow tools
SCRIPTS=(
    "agent-runner"
    "agent-mail-helper"
    "visual-session-manager"
    "monitor-agent-mail"
    "terminal-inject"
    "mail-monitor-ctl"
    "br-start-work"
    "bv-claim"
    "next-bead"
    "broadcast-to-swarm"
    "hook-bypass"
)

installed=0
for script in "${SCRIPTS[@]}"; do
    if [ -f "$SOURCE_DIR/$script" ]; then
        cp "$SOURCE_DIR/$script" "$INSTALL_DIR/$script"
        chmod +x "$INSTALL_DIR/$script"
        
        # Update lib paths in scripts to use installed location
        if grep -q "scripts/lib/" "$INSTALL_DIR/$script" 2>/dev/null; then
            sed -i.bak "s|scripts/lib/|$LIB_DIR/|g" "$INSTALL_DIR/$script"
            rm -f "$INSTALL_DIR/$script.bak"
        fi
        
        installed=$((installed + 1))
        echo "✓ Installed $script"
    else
        echo "⚠ Skipping $script (not found)"
    fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Installed $installed workflow tools to $INSTALL_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Installed commands:"
echo ""
echo "Core workflow:"
echo "  agent-runner              - Autonomous agent execution loop"
echo "  visual-session-manager    - fzf-based tmux session launcher"
echo "  agent-mail-helper         - MCP Agent Mail client"
echo ""
echo "Monitoring:"
echo "  monitor-agent-mail        - Real-time mail notifications"
echo "  mail-monitor-ctl          - Mail monitor daemon control"
echo "  terminal-inject           - Command queue injection"
echo ""
echo "Task management:"
echo "  br-start-work             - Start new bead workflow"
echo "  bv-claim                  - Claim next bead from queue"
echo "  next-bead                 - Get next recommended bead"
echo ""
echo "Multi-agent:"
echo "  broadcast-to-swarm        - Send message to all agents"
echo ""
echo "Utilities:"
echo "  hook-bypass               - Manage git hook bypass mode"
echo ""
echo "Prerequisites:"
echo "  - MCP Agent Mail server running (for agent mail features)"
echo "  - beads_rust (br) installed (for task management)"
echo "  - beads_viewer (bv) installed (for task visualization)"
echo "  - tmux (for session management)"
echo ""
