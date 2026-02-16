#!/usr/bin/env bash
# Set the ChatGPT conversation URL for the browser worker
#
# Usage:
#   ./scripts/chatgpt/set-conversation.sh "https://chatgpt.com/c/..."
#   ./scripts/chatgpt/set-conversation.sh     # shows current URL

set -euo pipefail

CONFIG_FILE=".flywheel/chatgpt.json"

# If no argument, show current config
if [ $# -eq 0 ]; then
    if [ -f "$CONFIG_FILE" ]; then
        echo "Current configuration:"
        cat "$CONFIG_FILE"
        echo ""
        echo "Conversation URL: $(jq -r .crt_url "$CONFIG_FILE")"
    else
        echo "No configuration found at: $CONFIG_FILE"
        echo ""
        echo "Usage: $0 <conversation-url>"
        exit 1
    fi
    exit 0
fi

CONVERSATION_URL="$1"

# Validate URL format
if [[ ! "$CONVERSATION_URL" =~ ^https://chatgpt\.com/ ]]; then
    echo "ERROR: Invalid ChatGPT URL format"
    echo "Expected: https://chatgpt.com/c/... or https://chatgpt.com/g/..."
    echo "Got: $CONVERSATION_URL"
    exit 1
fi

# Create .flywheel directory if needed
mkdir -p .flywheel

# Create or update config
cat > "$CONFIG_FILE" <<EOF
{
  "crt_url": "$CONVERSATION_URL",
  "mcp_server": "playwright-chatgpt",
  "writer_agent": "OrangeLantern"
}
EOF

echo "✓ Configuration updated: $CONFIG_FILE"
echo "✓ Conversation URL: $CONVERSATION_URL"
echo ""
echo "Now you can use send-to-worker.mjs without --conversation-url:"
echo "  node scripts/send-to-worker.mjs --message-file tmp/message.txt --out tmp/response.json"
