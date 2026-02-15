#!/bin/bash
# Stop supervisord gracefully
# Sends Ctrl+C to the supervisord tmux window

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/config/supervisord.conf"

# Get current session name
SESSION_NAME=$(tmux display-message -p "#{session_name}" 2>/dev/null || echo "agentcore")

echo "Stopping supervisord in session: $SESSION_NAME..."

# Check if supervisord window exists
if tmux list-windows -t "$SESSION_NAME" 2>/dev/null | grep -q "supervisord"; then
    # Send Ctrl+C to stop supervisord gracefully
    tmux send-keys -t "${SESSION_NAME}:supervisord" C-c 2>/dev/null
    echo "✓ Sent stop signal to supervisord"

    # Wait a moment for graceful shutdown
    sleep 2

    # Kill the window
    tmux kill-window -t "${SESSION_NAME}:supervisord" 2>/dev/null || true
    echo "✓ Supervisord window closed"
else
    echo "⚠️  No supervisord window found in session $SESSION_NAME"
fi

# Verify socket is gone
if [ -S "$PROJECT_ROOT/tmp/supervisor.sock" ]; then
    echo "⚠️  Socket file still exists, trying supervisorctl shutdown..."
    supervisorctl -c "$CONFIG_FILE" shutdown 2>/dev/null || true
    rm -f "$PROJECT_ROOT/tmp/supervisor.sock" 2>/dev/null || true
fi

echo "✓ Supervisord stopped"
