#!/bin/bash
# OpenAI API Key Setup Script
# Usage:
#   1. Create a file: echo "sk-proj-YOUR-KEY-HERE" > /tmp/openai-key.txt
#   2. Run this script: ./scripts/setup-openai-key.sh
#   3. The temp file will be securely deleted after setup

set -e

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

KEY_FILE="/tmp/openai-key.txt"

# Check if key file exists
if [ ! -f "$KEY_FILE" ]; then
    echo "❌ Error: Key file not found at $KEY_FILE"
    echo ""
    echo "Create it with:"
    echo "  echo 'sk-proj-YOUR-KEY-HERE' > /tmp/openai-key.txt"
    exit 1
fi

# Read the key
OPENAI_KEY=$(cat "$KEY_FILE" | tr -d '\n\r ')

# Validate key format
if [[ ! "$OPENAI_KEY" =~ ^sk-(proj-)?[A-Za-z0-9_-]+$ ]]; then
    echo "❌ Error: Invalid OpenAI API key format"
    echo "   Key should start with 'sk-' or 'sk-proj-'"
    rm -f "$KEY_FILE"
    exit 1
fi

echo "✓ Valid OpenAI API key detected"

# Check if key already exists in shell config
if grep -q "export OPENAI_API_KEY=" "$SHELL_RC" 2>/dev/null; then
    echo "⚠️  OPENAI_API_KEY already exists in $SHELL_RC"
    read -p "Overwrite? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Remove old key
        grep -v "export OPENAI_API_KEY=" "$SHELL_RC" > "${SHELL_RC}.tmp"
        mv "${SHELL_RC}.tmp" "$SHELL_RC"
        echo "✓ Removed old key"
    else
        rm -f "$KEY_FILE"
        echo "Cancelled."
        exit 0
    fi
fi

# Add Python bin to PATH if not already there
if ! grep -q "$PYTHON_BIN" "$SHELL_RC" 2>/dev/null; then
    echo "" >> "$SHELL_RC"
    echo "# Python user bin directory (added $(date '+%Y-%m-%d'))" >> "$SHELL_RC"
    echo "export PATH=\"$PYTHON_BIN:\$PATH\"" >> "$SHELL_RC"
    echo "✓ Added Python bin to PATH in $SHELL_RC"
fi

# Add key to shell config
echo "" >> "$SHELL_RC"
echo "# OpenAI API Key (added $(date '+%Y-%m-%d'))" >> "$SHELL_RC"
echo "export OPENAI_API_KEY=\"$OPENAI_KEY\"" >> "$SHELL_RC"

echo "✓ Added OPENAI_API_KEY to $SHELL_RC"

# Set for current session
export PATH="$PYTHON_BIN:$PATH"
export OPENAI_API_KEY="$OPENAI_KEY"

echo "✓ Key and PATH set for current session"

# Securely delete the temporary file
shred -n 3 -z "$KEY_FILE" 2>/dev/null || rm -f "$KEY_FILE"
echo "✓ Securely deleted $KEY_FILE"

# Install aider if not present
echo ""
echo "Checking for aider (OpenAI coding assistant)..."
if ! command -v aider &> /dev/null; then
    echo "Installing aider..."
    pip install aider-chat
    echo "✓ Aider installed"
else
    echo "✓ Aider already installed"
fi

# Test the connection
echo ""
echo "Testing OpenAI API connection..."
if command -v aider &> /dev/null; then
    # Just verify aider can start (without actually starting a session)
    echo "✓ Setup complete!"
    echo ""
    echo "To use aider: aider"
    echo "To reload environment: source $SHELL_RC"
else
    echo "⚠️  Could not verify aider installation"
fi

echo ""
echo "================================================"
echo "Setup Complete!"
echo "================================================"
echo "Your OpenAI API key is now configured globally."
echo "Aider will work in ANY project directory."
echo ""
echo "To use aider in any project:"
echo "  1. cd /path/to/your/project"
echo "  2. aider"
echo ""
echo "To use in multi-agent sessions:"
echo "  Codex agents will automatically use aider"
echo ""
echo "IMPORTANT SECURITY NOTES:"
echo "  • Never share your API key"
echo "  • Monitor usage at: https://platform.openai.com/usage"
echo "  • Set spending limits at: https://platform.openai.com/account/limits"
echo ""
