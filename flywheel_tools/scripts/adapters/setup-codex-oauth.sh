#!/bin/bash
# Codex CLI Setup Script with ChatGPT OAuth
# This script sets up Codex CLI to use your ChatGPT subscription instead of API billing
#
# Usage: ./scripts/setup-codex-oauth.sh
#
# Prerequisites: ChatGPT Plus or Pro subscription

set -e

echo "================================================"
echo "Codex CLI Setup with ChatGPT Subscription"
echo "================================================"
echo ""
echo "This script will set up Codex CLI to use your ChatGPT"
echo "subscription (Plus or Pro) for authentication."
echo ""

# Detect Python bin directory (macOS vs Linux)
if [[ "$OSTYPE" == "darwin"* ]]; then
    PYTHON_BIN="$HOME/Library/Python/3.9/bin"
else
    PYTHON_BIN="$HOME/.local/bin"
fi

# Detect shell RC file
if [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then
    SHELL_RC="$HOME/.bashrc"
else
    SHELL_RC="$HOME/.bash_profile"
fi

# Check for existing API key
if grep -q "export OPENAI_API_KEY=" "$SHELL_RC" 2>/dev/null; then
    echo "⚠️  WARNING: Found OPENAI_API_KEY in $SHELL_RC"
    echo ""
    echo "To use your ChatGPT subscription instead of API billing,"
    echo "you should remove the API key from your shell config."
    echo ""
    read -p "Remove OPENAI_API_KEY from $SHELL_RC? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Backup the file
        cp "$SHELL_RC" "${SHELL_RC}.backup.$(date +%Y%m%d-%H%M%S)"
        echo "✓ Created backup: ${SHELL_RC}.backup.$(date +%Y%m%d-%H%M%S)"

        # Remove API key lines
        grep -v "export OPENAI_API_KEY=" "$SHELL_RC" > "${SHELL_RC}.tmp"
        mv "${SHELL_RC}.tmp" "$SHELL_RC"
        echo "✓ Removed OPENAI_API_KEY from $SHELL_RC"

        # Unset for current session
        unset OPENAI_API_KEY
        echo "✓ Unset OPENAI_API_KEY for current session"
    else
        echo "⚠️  Keeping API key. Note: This may cause API charges!"
    fi
    echo ""
fi

# Check if Codex CLI is installed
echo "Checking for Codex CLI..."
if command -v codex &> /dev/null; then
    CODEX_VERSION=$(codex --version 2>/dev/null || echo "unknown")
    echo "✓ Codex CLI is already installed (version: $CODEX_VERSION)"
else
    echo "Installing Codex CLI..."

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

    # Install Codex CLI globally
    npm install -g @openai/codex-cli

    if command -v codex &> /dev/null; then
        echo "✓ Codex CLI installed successfully"
    else
        echo "❌ Error: Codex CLI installation failed"
        echo "   Try running: npm install -g @openai/codex-cli"
        exit 1
    fi
fi

# Add npm global bin to PATH if needed
NPM_BIN="$HOME/.npm-global/bin"
if [ -d "$NPM_BIN" ] && ! grep -q "$NPM_BIN" "$SHELL_RC" 2>/dev/null; then
    echo "" >> "$SHELL_RC"
    echo "# npm global bin directory (added $(date '+%Y-%m-%d'))" >> "$SHELL_RC"
    echo "export PATH=\"$NPM_BIN:\$PATH\"" >> "$SHELL_RC"
    echo "✓ Added npm global bin to PATH in $SHELL_RC"
fi

# Add Python bin to PATH if not already there
if ! grep -q "$PYTHON_BIN" "$SHELL_RC" 2>/dev/null; then
    echo "" >> "$SHELL_RC"
    echo "# Python user bin directory (added $(date '+%Y-%m-%d'))" >> "$SHELL_RC"
    echo "export PATH=\"$PYTHON_BIN:\$PATH\"" >> "$SHELL_RC"
    echo "✓ Added Python bin to PATH in $SHELL_RC"
fi

echo ""
echo "================================================"
echo "Authentication Setup"
echo "================================================"
echo ""
echo "Now we'll authenticate Codex CLI with your ChatGPT account."
echo "This will open a browser window for you to sign in."
echo ""
echo "IMPORTANT: Make sure you have:"
echo "  ✓ ChatGPT Plus or Pro subscription"
echo "  ✓ Multi-factor authentication enabled (required by Codex)"
echo ""

# Check if already authenticated
if [ -f "$HOME/.codex/auth.json" ]; then
    echo "⚠️  Existing Codex authentication found"
    read -p "Re-authenticate? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        codex logout
        echo "✓ Logged out"
    else
        echo "Keeping existing authentication"
        echo ""
        echo "Setup complete!"
        exit 0
    fi
fi

echo ""
echo "Starting authentication..."
echo "A browser window will open shortly."
echo ""

# Authenticate with ChatGPT (OAuth)
codex login

echo ""
echo "================================================"
echo "Setup Complete!"
echo "================================================"
echo ""
echo "✓ Codex CLI is configured with your ChatGPT subscription"
echo ""
echo "NEXT STEPS:"
echo ""
echo "1. Test Codex CLI:"
echo "   codex 'Hello, are you working?'"
echo ""
echo "2. Start Agent Flywheel:"
echo "   cd $(pwd)"
echo "   ./start"
echo ""
echo "IMPORTANT NOTES:"
echo "  • Requires active ChatGPT Plus/Pro subscription"
echo "  • Keep MFA enabled for security"
echo ""
echo "To reload your shell configuration:"
echo "  source $SHELL_RC"
echo ""
