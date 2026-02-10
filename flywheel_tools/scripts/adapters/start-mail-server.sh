#!/bin/bash
# Start MCP Agent Mail HTTP server for notifications

# Source shared project configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/project-config.sh"

PID_FILE="$PIDS_DIR/mail-server.pid"
LOG_FILE="$LOGS_DIR/mail-server.log"

# Mail server configuration (can be overridden via environment variables)
MCP_AGENT_MAIL_DIR="${MCP_AGENT_MAIL_DIR:-$HOME/mcp_agent_mail}"
export MCP_AGENT_MAIL_BACKEND=git
export MCP_AGENT_MAIL_GIT_REPO="${MCP_AGENT_MAIL_GIT_REPO:-$HOME/.mcp_agent_mail_local_repo}"
export MCP_AGENT_MAIL_HTTP_PORT=8765

# Check if mail server directory exists
if [ ! -d "$MCP_AGENT_MAIL_DIR" ]; then
    echo "❌ Mail server directory not found: $MCP_AGENT_MAIL_DIR"
    echo "   Please install mcp_agent_mail or set MCP_AGENT_MAIL_DIR environment variable"
    exit 1
fi

# Check if already running
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p "$PID" > /dev/null 2>&1; then
        echo "✅ Mail server already running (PID: $PID)"
        exit 0
    else
        rm -f "$PID_FILE"
    fi
fi

# Create directories
mkdir -p "$(dirname "$PID_FILE")" "$(dirname "$LOG_FILE")"

echo "📬 Starting MCP Agent Mail HTTP server..."

# Load or generate token
if [ -f "$MCP_AGENT_MAIL_DIR/.env" ]; then
    export HTTP_BEARER_TOKEN=$(grep HTTP_BEARER_TOKEN "$MCP_AGENT_MAIL_DIR/.env" | cut -d'=' -f2)
fi

# Start server using uv run
cd "$MCP_AGENT_MAIL_DIR"
nohup uv run python -m mcp_agent_mail.cli serve-http > "$LOG_FILE" 2>&1 &
SERVER_PID=$!

# Save PID
echo "$SERVER_PID" > "$PID_FILE"

# Wait for server to start
sleep 3

# Check if running
if ps -p "$SERVER_PID" > /dev/null 2>&1; then
    echo "✅ Mail server started (PID: $SERVER_PID)"
    echo "   Port: 8765"
    echo "   Log: $LOG_FILE"
    echo "   Use './scripts/stop-mail-server.sh' to stop"
else
    echo "❌ Failed to start mail server"
    echo "   Check log: $LOG_FILE"
    rm -f "$PID_FILE"
    exit 1
fi
