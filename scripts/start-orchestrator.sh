#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# State
RESTART_COUNT=0
MAX_RESTARTS=999  # Essentially unlimited
AGENT_NAME="Orchestrator"

# Print banner
echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════════╗"
echo "  ║          Orchestrator Agent                   ║"
echo "  ║   ChatGPT Partner · Plan Orchestration        ║"
echo "  ╚═══════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# Check for conversation URL
if [ ! -f ".flywheel/chatgpt.json" ]; then
  echo -e "${YELLOW}⚠ Warning: .flywheel/chatgpt.json not found${NC}"
  echo -e "${YELLOW}  Create it with:${NC}"
  echo -e "${YELLOW}  {\"crt_url\": \"https://chatgpt.com/c/YOUR-CONVERSATION-ID\"}${NC}"
  echo ""
  read -p "Press Enter to continue anyway..."
else
  CONV_URL=$(jq -r .crt_url .flywheel/chatgpt.json 2>/dev/null || echo "")
  if [ -n "$CONV_URL" ] && [ "$CONV_URL" != "null" ]; then
    echo -e "${GREEN}✓ Conversation URL configured: ${CONV_URL}${NC}"
  else
    echo -e "${YELLOW}⚠ Warning: crt_url not set in .flywheel/chatgpt.json${NC}"
  fi
fi
echo ""

# Register with agent-mail system
echo -e "${GREEN}Registering with agent-mail system...${NC}"
./scripts/agent-mail-helper.sh register "Orchestrator - works with ChatGPT to create implementation plans"

# Get the assigned name
ASSIGNED_NAME=$(./scripts/agent-mail-helper.sh whoami)
AGENT_NAME="${ASSIGNED_NAME:-Orchestrator}"
echo -e "${GREEN}✓ Registered as: $AGENT_NAME${NC}"
echo ""

# Load orchestrator instructions
INSTRUCTIONS_FILE=".flywheel/orchestrator-instructions.md"

if [ ! -f "$INSTRUCTIONS_FILE" ]; then
  echo -e "${YELLOW}⚠ Instructions file not found: $INSTRUCTIONS_FILE${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Using instructions: $INSTRUCTIONS_FILE${NC}"
echo ""

# Auto-restart loop
while true; do
    RESTART_COUNT=$((RESTART_COUNT + 1))

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Launch #${RESTART_COUNT}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Load instructions into system prompt
    SYSTEM_PROMPT=$(cat "$INSTRUCTIONS_FILE")

    echo -e "${GREEN}Launching orchestrator agent...${NC}"
    echo -e "${YELLOW}Type /exit to restart with same instructions${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
    echo ""

    # Launch Claude with orchestrator instructions
    claude \
        --dangerously-skip-permissions \
        --append-system-prompt "$SYSTEM_PROMPT" \
        || true

    exit_code=$?

    echo ""
    echo -e "${YELLOW}Orchestrator exited (code: $exit_code)${NC}"
    echo -e "${GREEN}Restarting in 2 seconds... (restart $RESTART_COUNT)${NC}"
    echo ""

    sleep 2
done
