#!/usr/bin/env bash
set -euo pipefail

# Bridge Agent Loop - Processes batch plan requests from agent-mail

AGENT_IDENTITY="${AGENT_IDENTITY:-ChatGPTBridge}"
CHECK_INTERVAL="${BRIDGE_CHECK_INTERVAL:-3}"

# Source mail configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$PROJECT_ROOT/scripts/lib/project-config.sh"

MAIL_SERVER="${MAIL_SERVER:-http://127.0.0.1:8765}"
MCP_AGENT_MAIL_DIR="${MCP_AGENT_MAIL_DIR:-$HOME/mcp_agent_mail}"
TOKEN_FILE="$MCP_AGENT_MAIL_DIR/.env"

if [ ! -f "$TOKEN_FILE" ]; then
    echo "Error: Token file not found at $TOKEN_FILE"
    exit 1
fi
TOKEN=$(grep HTTP_BEARER_TOKEN "$TOKEN_FILE" | cut -d'=' -f2)

echo "=== ChatGPT Bridge Agent ==="
echo "Identity: $AGENT_IDENTITY"
echo "Check interval: ${CHECK_INTERVAL}s"

# Register the bridge agent with the mail system
echo "Registering $AGENT_IDENTITY with mail system..."
cat > /tmp/bridge-register.json << EOF
{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "register_agent",
    "arguments": {
      "project_key": "$MAIL_PROJECT_KEY",
      "program": "bash-bridge",
      "model": "chatgpt",
      "name": "$AGENT_IDENTITY",
      "task_description": "ChatGPT bridge for batch planning"
    }
  },
  "id": $(date +%s)
}
EOF

curl -s -X POST "$MAIL_SERVER/mcp" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/bridge-register.json >/dev/null 2>&1
rm -f /tmp/bridge-register.json

echo "✓ Registered"
echo "Listening for BATCH_PLAN requests..."
echo ""

while true; do
  # Check for incoming batch-plan requests via MCP API
  # Format: to:ChatGPTBridge, subject:BATCH_PLAN, body: { "beads": ["bd-xxx", "bd-yyy"] }

  # Fetch inbox using MCP API
  cat > /tmp/bridge-inbox.json << EOF
{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "fetch_inbox",
    "arguments": {
      "project_key": "$MAIL_PROJECT_KEY",
      "agent_name": "$AGENT_IDENTITY",
      "limit": 10,
      "include_bodies": true
    }
  },
  "id": $(date +%s)
}
EOF

  INBOX_RESPONSE=$(curl -s -X POST "$MAIL_SERVER/mcp" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d @/tmp/bridge-inbox.json 2>/dev/null || echo "")

  rm -f /tmp/bridge-inbox.json

  # Filter for BATCH_PLAN messages
  REQUEST=$(echo "$INBOX_RESPONSE" | jq -c '[.result.structuredContent.result[] | select(.subject == "BATCH_PLAN")] | .[0] // null' 2>/dev/null || echo "")

  if [ -n "$REQUEST" ] && [ "$REQUEST" != "null" ]; then
    MAIL_ID=$(echo "$REQUEST" | jq -r '.id // empty')
    SENDER=$(echo "$REQUEST" | jq -r '.from // empty')
    # Parse beads from body (could be JSON string or object)
    BODY=$(echo "$REQUEST" | jq -r '.body_md // empty')
    BEADS=$(echo "$BODY" | jq -r '.beads // empty' 2>/dev/null || echo "")

    if [ -z "$MAIL_ID" ] || [ -z "$SENDER" ] || [ -z "$BEADS" ]; then
      echo "[$(date +%T)] Malformed request, skipping"
      sleep "$CHECK_INTERVAL"
      continue
    fi

    # Guard #6: Idempotency - check if we already processed this request
    SENT_MARKER=".flywheel/bridge/sent/${MAIL_ID}.json"
    if [ -f "$SENT_MARKER" ]; then
      echo "[$(date +%T)] ⏭️  Request $MAIL_ID already processed, skipping"
      sleep "$CHECK_INTERVAL"
      continue
    fi

    echo "[$(date +%T)] 📨 Batch plan request from: $SENDER"
    echo "  Beads: $BEADS"
    echo "  Mail ID: $MAIL_ID"

    # Convert JSON array to comma-separated list if needed
    BEAD_LIST=$(echo "$BEADS" | jq -r 'if type == "array" then join(",") else . end')

    # Run batch planner
    echo "  Running batch-plan.mjs..."
    node scripts/chatgpt/batch-plan.mjs \
      --beads "$BEAD_LIST" \
      --out "tmp/batch-response-${MAIL_ID}.json"

    PLAN_FILE="tmp/batch-response-${MAIL_ID}.json"

    if [ -f "$PLAN_FILE" ]; then
      echo "  ✓ Plans generated"

      # Reply to sender with results using agent-mail-helper.sh
      PLAN_CONTENT=$(cat "$PLAN_FILE")
      ./scripts/agent-mail-helper.sh send "$SENDER" "BATCH_PLAN_RESPONSE" "$PLAN_CONTENT"

      echo "  ✓ Response sent to $SENDER"

      # Write idempotency marker (Guard #6)
      mkdir -p "$(dirname "$SENT_MARKER")"
      echo "{\"mail_id\":\"$MAIL_ID\",\"sender\":\"$SENDER\",\"timestamp\":\"$(date -Iseconds)\",\"beads\":$BEADS}" > "$SENT_MARKER"
      echo "  ✓ Idempotency marker written"
    else
      echo "  ✗ Failed to generate plans"

      # Send error response
      ERROR_BODY=$(cat <<EOF
{
  "error": "Failed to generate batch plans",
  "beads": "$BEAD_LIST",
  "timestamp": "$(date -Iseconds)"
}
EOF
)
      ./scripts/agent-mail-helper.sh send "$SENDER" "BATCH_PLAN_ERROR" "$ERROR_BODY"
    fi

    echo ""
  fi

  sleep "$CHECK_INTERVAL"
done
