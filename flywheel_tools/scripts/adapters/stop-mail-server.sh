#!/bin/bash
# Stop MCP Agent Mail HTTP server

# Source shared project configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/project-config.sh"

PID_FILE="$PIDS_DIR/mail-server.pid"

if [ ! -f "$PID_FILE" ]; then
    echo "❌ Mail server not running"
    exit 1
fi

PID=$(cat "$PID_FILE")

if ps -p "$PID" > /dev/null 2>&1; then
    echo "📭 Stopping mail server (PID: $PID)..."
    kill "$PID"
    rm -f "$PID_FILE"
    echo "✅ Mail server stopped"
else
    echo "❌ Mail server not running (stale PID file)"
    rm -f "$PID_FILE"
    exit 1
fi
