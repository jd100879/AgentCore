#!/usr/bin/env bash
set -euo pipefail

# Start Bridge Agent - Auto-restarting ChatGPT bridge coordinator

BRIDGE_IDENTITY="${BRIDGE_IDENTITY:-ChatGPTBridge}"
SESSION_NAME="${TMUX_SESSION:-agentcore}"
WINDOW_NAME="bridge"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Starting Bridge Agent ==="
echo "Identity: $BRIDGE_IDENTITY"
echo "Session: $SESSION_NAME"
echo "Window: $WINDOW_NAME"
echo "Project: $PROJECT_ROOT"
echo ""

# Create session if it doesn't exist
if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  echo "Creating tmux session: $SESSION_NAME"
  tmux new-session -d -s "$SESSION_NAME" -c "$PROJECT_ROOT"
fi

# Kill existing bridge window if present
if tmux list-windows -t "$SESSION_NAME" -F "#{window_name}" | grep -q "^${WINDOW_NAME}$"; then
  echo "Killing existing bridge window..."
  tmux kill-window -t "${SESSION_NAME}:${WINDOW_NAME}"
fi

# Create bridge window with auto-restart loop
echo "Creating bridge window with auto-restart..."
tmux new-window -t "$SESSION_NAME" -n "$WINDOW_NAME" -c "$PROJECT_ROOT" bash -c "
  export AGENT_IDENTITY='$BRIDGE_IDENTITY'
  export AGENT_ROLE='bridge'

  while true; do
    echo ''
    echo '╔════════════════════════════════════════╗'
    echo '║   ChatGPT Bridge Agent Starting...    ║'
    echo '╚════════════════════════════════════════╝'
    echo ''
    echo 'Identity: $BRIDGE_IDENTITY'
    echo 'Started: \$(date)'
    echo ''

    # Run the bridge agent loop
    bash scripts/chatgpt/bridge-agent-loop.sh

    EXIT_CODE=\$?

    echo ''
    echo '╔════════════════════════════════════════╗'
    echo \"║  Bridge exited with code: \$EXIT_CODE\"
    echo '╚════════════════════════════════════════╝'
    echo ''

    if [ \$EXIT_CODE -eq 0 ]; then
      echo 'Clean exit. Restarting in 2 seconds...'
      sleep 2
    elif [ \$EXIT_CODE -eq 130 ]; then
      echo 'Interrupted (Ctrl-C). Stopping bridge.'
      break
    else
      echo 'Error exit. Restarting in 5 seconds...'
      sleep 5
    fi
  done

  echo ''
  echo 'Bridge agent stopped.'
  echo 'Press ENTER to close this window.'
  read
"

echo "✓ Bridge agent started in window: ${SESSION_NAME}:${WINDOW_NAME}"
echo ""
echo "To view the bridge agent:"
echo "  tmux attach -t $SESSION_NAME"
echo "  tmux select-window -t ${SESSION_NAME}:${WINDOW_NAME}"
echo ""
echo "To send a batch plan request from another agent:"
echo "  ./scripts/agent-mail-helper.sh send $BRIDGE_IDENTITY \\"
echo "    'BATCH_PLAN' \\"
echo "    '{\"beads\": [\"bd-xxx\", \"bd-yyy\"]}'"
echo ""
