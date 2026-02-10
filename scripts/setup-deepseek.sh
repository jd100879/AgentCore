#!/bin/bash
# DeepSeek CLI Setup Script
# This script sets up deepseek-cli with your API key
#
# Usage: ./scripts/setup-deepseek.sh
#
# Prerequisites: DeepSeek API key from https://platform.deepseek.com/

set -e

echo "================================================"
echo "DeepSeek CLI Setup"
echo "================================================"
echo ""
echo "This script will install and configure deepseek-cli"
echo "with your DeepSeek API key."
echo ""

# Detect shell RC file
if [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then
    SHELL_RC="$HOME/.bashrc"
else
    SHELL_RC="$HOME/.bash_profile"
fi

# Check if Python3 is installed
if ! command -v python3 &> /dev/null; then
    echo "❌ Error: python3 is not installed"
    echo ""
    echo "Please install Python 3 first:"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "  brew install python3"
    else
        echo "  sudo apt install python3"
    fi
    exit 1
fi

echo "✓ Python3 is installed"
echo ""
echo "Note: Using DeepSeek API wrapper script (no package installation needed)"

echo ""
echo "================================================"
echo "API Key Setup"
echo "================================================"
echo ""
echo "You need a DeepSeek API key to use this service."
echo ""
echo "Get your API key from: https://platform.deepseek.com/"
echo "Press Enter without typing anything to skip setup for now."
echo ""
read -p "Enter your DeepSeek API key (or press Enter to skip): " DEEPSEEK_API_KEY

if [ -z "$DEEPSEEK_API_KEY" ]; then
    echo ""
    echo "⚠️  Setup skipped - no API key provided"
    echo ""
    echo "DeepSeek agents will not work without an API key."
    echo "You can run this setup later:"
    echo "  ./scripts/setup-deepseek.sh"
    echo ""
    exit 0
fi

# Add API key to shell config
if ! grep -q "export DEEPSEEK_API_KEY=" "$SHELL_RC" 2>/dev/null; then
    echo "" >> "$SHELL_RC"
    echo "# DeepSeek API key (added $(date '+%Y-%m-%d'))" >> "$SHELL_RC"
    echo "export DEEPSEEK_API_KEY='$DEEPSEEK_API_KEY'" >> "$SHELL_RC"
    echo "✓ Added DEEPSEEK_API_KEY to $SHELL_RC"
else
    # Update existing key
    sed -i.backup "s/export DEEPSEEK_API_KEY=.*/export DEEPSEEK_API_KEY='$DEEPSEEK_API_KEY'/" "$SHELL_RC"
    echo "✓ Updated DEEPSEEK_API_KEY in $SHELL_RC"
fi

# Export for current session
export DEEPSEEK_API_KEY="$DEEPSEEK_API_KEY"

echo ""
echo "================================================"
echo "Setup Complete!"
echo "================================================"
echo ""
echo "✓ DeepSeek CLI is configured"
echo ""
echo "NEXT STEPS:"
echo ""
echo "1. Test DeepSeek CLI:"
echo "   deepseek 'Hello, are you working?'"
echo ""
echo "2. Start Agent Flywheel and select DeepSeek agents:"
echo "   cd $(pwd)"
echo "   ./start"
echo ""
echo "To reload your shell configuration:"
echo "  source $SHELL_RC"
echo ""
