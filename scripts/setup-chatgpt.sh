#!/bin/bash
# ChatGPT Authentication Setup Script
# This script sets up ChatGPT authentication via browser (OAuth)
#
# Usage: ./scripts/setup-chatgpt.sh
#
# Prerequisites: ChatGPT Plus or Pro subscription

set -e

echo "================================================"
echo "ChatGPT Authentication Setup"
echo "================================================"
echo ""
echo "This script will authenticate you with ChatGPT"
echo "using your browser (OAuth)."
echo ""

# Check if codex is installed
if ! command -v codex &> /dev/null; then
    echo "❌ Error: codex CLI is not installed"
    echo ""
    echo "Please install Codex CLI first:"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "  brew install openai-codex"
    else
        echo "  Visit: https://openai.com/codex-cli"
    fi
    exit 1
fi

echo "✓ Codex CLI is installed ($(codex --version))"
echo ""

# Check if already authenticated
if [ -f "$HOME/.codex/auth.json" ]; then
    echo "You appear to be already authenticated."
    echo ""
    read -p "Re-authenticate? [y/N]: " REAUTH || REAUTH=""
    REAUTH=${REAUTH:-N}

    if [[ ! "$REAUTH" =~ ^[Yy]$ ]]; then
        echo ""
        echo "✓ Using existing authentication"
        echo ""
        exit 0
    fi
fi

echo "================================================"
echo "Browser Authentication"
echo "================================================"
echo ""
echo "This will open your browser to sign in with ChatGPT."
echo ""
echo "Requirements:"
echo "  • ChatGPT Plus or Pro subscription"
echo "  • You'll be prompted to authorize access"
echo ""
read -p "Press Enter to open browser and authenticate (or Ctrl+C to cancel): "

echo ""
echo "Opening browser for authentication..."
echo ""

# Run codex login
if codex login; then
    echo ""
    echo "================================================"
    echo "Setup Complete!"
    echo "================================================"
    echo ""
    echo "✓ ChatGPT authentication successful"
    echo ""
    echo "Your credentials are stored in: ~/.codex/auth.json"
    echo ""
    echo "NEXT STEPS:"
    echo ""
    echo "1. Test ChatGPT access:"
    echo "   codex 'Hello, are you working?'"
    echo ""
    echo "2. Start Agent Flywheel and select ChatGPT agents:"
    echo "   cd $(pwd)"
    echo "   ./start"
    echo ""
else
    echo ""
    echo "❌ Authentication failed"
    echo ""
    echo "Please try again or visit: https://chat.openai.com"
    echo "to ensure your ChatGPT account is active."
    echo ""
    exit 1
fi
