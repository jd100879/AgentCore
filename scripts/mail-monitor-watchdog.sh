#!/bin/bash
# Mail Monitor Watchdog - Restarts dead monitors automatically
# Run this in background to ensure monitors stay alive

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK_INTERVAL="${1:-30}"  # Check every 30 seconds by default

echo "[$(date)] Mail monitor watchdog started (check interval: ${CHECK_INTERVAL}s)"

check_count=0

while true; do

    # Find all active agent panes that should have monitors
    tmux list-panes -a -F "#{session_name}:#{window_index}.#{pane_index} #{pane_current_path}" 2>/dev/null | \
    grep "$PROJECT_ROOT" | \
    while read pane_id pane_path; do
        # Check if this pane has an agent identity file
        safe_pane=$(echo "$pane_id" | tr ':.' '-')
        identity_file="$PROJECT_ROOT/panes/${safe_pane}.identity"
        
        if [ -f "$identity_file" ]; then
            # Extract agent name from identity file
            agent_name=$(jq -r '.agent_mail_name // empty' "$identity_file" 2>/dev/null)
            
            if [ -n "$agent_name" ] && [ "$agent_name" != "null" ]; then
                # Check if monitor is running for this agent
                if ! pgrep -f "monitor-agent-mail-to-terminal.sh $agent_name" > /dev/null; then
                    echo "[$(date)] Restarting monitor for $agent_name (pane: $pane_id)"

                    # Restart monitor using the control script
                    MONITOR_SAFE_PANE="$safe_pane" "$SCRIPT_DIR/mail-monitor-ctl.sh" restart
                fi
            fi
        fi
    done

    # Log check cycle completion (every 5 minutes to avoid log spam)
    check_count=$((check_count + 1))
    if [ $((check_count % 10)) -eq 0 ]; then
        echo "[$(date)] Watchdog check cycle #$check_count complete"
    fi

    sleep "$CHECK_INTERVAL"
done
