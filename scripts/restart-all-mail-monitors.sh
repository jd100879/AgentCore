#!/bin/bash
# Restart all mail monitors after MCP container rebuild
# Call this after docker-compose up/rebuild

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🔄 Restarting all mail monitors after MCP container rebuild..."

# Kill all old monitors for this project
pkill -f "monitor-agent-mail-to-terminal.sh.*$PROJECT_ROOT"
sleep 2

# Find all active agent panes and restart their monitors
restart_count=0

for pane_id in $(tmux list-panes -a -F "#{session_name}:#{window_index}.#{pane_index}" 2>/dev/null); do
    safe_pane=$(echo "$pane_id" | tr ':.' '-')
    identity_file="$PROJECT_ROOT/panes/${safe_pane}.identity"

    if [ -f "$identity_file" ]; then
        agent_name=$(jq -r '.agent_mail_name // .agent_name // empty' "$identity_file" 2>/dev/null)

        if [ -n "$agent_name" ] && [ "$agent_name" != "null" ]; then
            echo "  ↻ Restarting monitor for $agent_name (pane: $pane_id)"
            MONITOR_SAFE_PANE="$safe_pane" "$SCRIPT_DIR/mail-monitor-ctl.sh" start 2>/dev/null
            restart_count=$((restart_count + 1))
        fi
    fi
done

echo "✅ Restarted $restart_count mail monitors"
