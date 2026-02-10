#!/bin/bash
# Grok CLI Setup Script
# This script sets up grok-cli with your xAI API key
#
# Usage: ./scripts/setup-grok.sh
#
# Prerequisites: xAI API key from https://x.ai/

set -e

echo "================================================"
echo "Grok CLI Setup"
echo "================================================"
echo ""
echo "This script will install and configure grok-cli"
echo "with your xAI API key."
echo ""

# Detect shell RC file
if [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then
    SHELL_RC="$HOME/.bashrc"
else
    SHELL_RC="$HOME/.bash_profile"
fi

# Check if npm is installed
if ! command -v npm &> /dev/null; then
    echo "❌ Error: npm is not installed"
    echo ""
    echo "Please install Node.js and npm first:"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "  brew install node"
    else
        echo "  sudo apt install nodejs npm"
    fi
    exit 1
fi

# Install grok-cli globally
echo "Installing grok-cli..."
echo "Note: This requires administrator privileges"
sudo npm install -g @vibe-kit/grok-cli

if command -v grok &> /dev/null; then
    echo "✓ grok-cli installed successfully"
else
    echo "❌ Error: grok-cli installation failed"
    exit 1
fi

echo ""
echo "================================================"
echo "API Key Setup"
echo "================================================"
echo ""
echo "You need an xAI API key to use Grok."
echo ""
echo "Get your API key from: https://console.x.ai/"
echo ""
echo "Press Enter without typing anything to skip setup for now."
echo ""
read -p "Enter your xAI API key (or press Enter to skip): " XAI_API_KEY

if [ -z "$XAI_API_KEY" ]; then
    echo ""
    echo "⚠️  Setup skipped - no API key provided"
    echo ""
    echo "Grok agents will not work without an API key."
    echo "You can run this setup later:"
    echo "  ./scripts/setup-grok.sh"
    echo ""
    exit 0
fi

# Add API key to shell config
if ! grep -q "export XAI_API_KEY=" "$SHELL_RC" 2>/dev/null; then
    echo "" >> "$SHELL_RC"
    echo "# xAI API key for Grok (added $(date '+%Y-%m-%d'))" >> "$SHELL_RC"
    echo "export XAI_API_KEY='$XAI_API_KEY'" >> "$SHELL_RC"
    echo "✓ Added XAI_API_KEY to $SHELL_RC"
else
    # Update existing key
    sed -i.backup "s/export XAI_API_KEY=.*/export XAI_API_KEY='$XAI_API_KEY'/" "$SHELL_RC"
    echo "✓ Updated XAI_API_KEY in $SHELL_RC"
fi

# Export for current session
export XAI_API_KEY="$XAI_API_KEY"

echo ""
echo "================================================"
echo "Setup Complete!"
echo "================================================"
echo ""
echo "✓ Grok CLI is configured"
echo ""
echo "NEXT STEPS:"
echo ""
echo "1. Test Grok CLI:"
echo "   grok 'Hello, are you working?'"
echo ""
echo "2. Start Agent Flywheel and select Grok agents:"
echo "   cd $(pwd)"
echo "   ./start"
echo ""
echo "AVAILABLE MODELS:"
echo "  • grok-3-mini-beta  (default, reasoning, cheaper)"
echo "  • grok-3-beta       (fast, no reasoning)"
echo "  • grok-4-latest     (reasoning, expensive, slow)"
echo ""
echo "To reload your shell configuration:"
echo "  source $SHELL_RC"
echo ""
