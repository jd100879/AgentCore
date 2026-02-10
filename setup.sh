#!/bin/bash
# AgentCore Setup Script
# Clones all required repositories and prepares the environment

set -e

AGENTCORE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$AGENTCORE_ROOT"

echo "================================================"
echo "AgentCore Setup"
echo "================================================"
echo ""

# Clone core repositories
echo "📦 Cloning core repositories..."
echo ""

repos=(
    "https://github.com/Dicklesworthstone/mcp_agent_mail.git"
    "https://github.com/Dicklesworthstone/beads_rust.git"
    "https://github.com/Dicklesworthstone/beads_viewer.git"
    "https://github.com/Dicklesworthstone/coding_agent_session_search.git"
    "https://github.com/Dicklesworthstone/ultimate_bug_scanner.git"
    "https://github.com/Dicklesworthstone/named_tmux_manager.git"
)

for repo in "${repos[@]}"; do
    repo_name=$(basename "$repo" .git)
    if [ -d "$repo_name" ]; then
        echo "✓ $repo_name already exists, skipping..."
    else
        echo "→ Cloning $repo_name..."
        git clone "$repo" || echo "⚠ Failed to clone $repo_name"
    fi
done

echo ""
echo "================================================"
echo "✅ Repository cloning complete!"
echo "================================================"
echo ""
echo "Next steps:"
echo "1. Install MCP Agent Mail: cd mcp_agent_mail && ./install.sh"
echo "2. Build beads_rust: cd beads_rust && cargo build --release"
echo "3. Install UBS: curl -sSL https://raw.githubusercontent.com/Dicklesworthstone/ultimate_bug_scanner/main/install.sh | bash"
echo ""
