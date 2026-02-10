#!/bin/bash
# Fixed install script for model adapters
set -euo pipefail

INSTALL_DIR="${HOME}/.local/bin"
LIB_DIR="${HOME}/.local/lib/agent_workflow"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing AI model adapters to $INSTALL_DIR..."
echo ""

mkdir -p "$INSTALL_DIR"

# Install Grok adapter
if [ -f "$SOURCE_DIR/grok/grok-claude-wrapper" ]; then
    cp "$SOURCE_DIR/grok/grok-claude-wrapper" "$INSTALL_DIR/grok-claude-wrapper"
    chmod +x "$INSTALL_DIR/grok-claude-wrapper"
    
    # Fix lib path to use centralized location
    sed -i.bak "s|\$SCRIPT_DIR/lib/|$LIB_DIR/|g" "$INSTALL_DIR/grok-claude-wrapper"
    rm -f "$INSTALL_DIR/grok-claude-wrapper.bak"
    echo "✓ Installed grok-claude-wrapper"
else
    echo "⚠ Skipping grok-claude-wrapper (not found)"
fi

# Install DeepSeek adapter
if [ -f "$SOURCE_DIR/deepseek/deepseek-claude-wrapper" ]; then
    cp "$SOURCE_DIR/deepseek/deepseek-claude-wrapper" "$INSTALL_DIR/deepseek-claude-wrapper"
    chmod +x "$INSTALL_DIR/deepseek-claude-wrapper"
    
    # Fix lib path to use centralized location
    sed -i.bak "s|\$SCRIPT_DIR/lib/|$LIB_DIR/|g" "$INSTALL_DIR/deepseek-claude-wrapper"
    rm -f "$INSTALL_DIR/deepseek-claude-wrapper.bak"
    echo "✓ Installed deepseek-claude-wrapper"
else
    echo "⚠ Skipping deepseek-claude-wrapper (not found)"
fi

# Install DeepSeek proxy
if [ -f "$SOURCE_DIR/deepseek/deepseek-compact-proxy.py" ]; then
    cp "$SOURCE_DIR/deepseek/deepseek-compact-proxy.py" "$INSTALL_DIR/deepseek-compact-proxy.py"
    chmod +x "$INSTALL_DIR/deepseek-compact-proxy.py"
    echo "✓ Installed deepseek-compact-proxy.py"
fi

if [ -f "$SOURCE_DIR/deepseek/start-deepseek-proxy.sh" ]; then
    cp "$SOURCE_DIR/deepseek/start-deepseek-proxy.sh" "$INSTALL_DIR/start-deepseek-proxy"
    chmod +x "$INSTALL_DIR/start-deepseek-proxy"
    echo "✓ Installed start-deepseek-proxy"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Model adapters installed successfully"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Note: Model adapters share library files with agent_workflow"
echo "      Location: $LIB_DIR"
echo ""
echo "Setup Instructions:"
echo ""
echo "Grok (xAI):"
echo "  1. Get API key from https://console.x.ai/"
echo "  2. Run setup: cd ~/Projects/AgentCore/tools/model-adapters/grok && ./setup-grok.sh"
echo "  3. Use: grok-claude-wrapper"
echo ""
echo "DeepSeek:"
echo "  1. Get API key from https://platform.deepseek.com/"
echo "  2. Run setup: cd ~/Projects/AgentCore/tools/model-adapters/deepseek && ./setup-deepseek.sh"
echo "  3. Use: deepseek-claude-wrapper"
echo ""
