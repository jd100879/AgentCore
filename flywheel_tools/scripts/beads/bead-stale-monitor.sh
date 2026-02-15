#!/bin/bash
# Bead stale monitor - sends reminders for inactive beads
# Checks beads with status=in_progress, sends SystemNotify if no activity for 15 min

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Go up 3 levels: beads -> scripts -> flywheel_tools -> project root
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# Source shared project configuration
source "$SCRIPT_DIR/lib/project-config.sh"
LOG_FILE="${PROJECT_DIR}/.beads/agent-activity.jsonl"
LOG_SCRIPT="${SCRIPT_DIR}/log-bead-activity.sh"
PROJECT_KEY="${MAIL_PROJECT_KEY:-/Users/james/Projects/agent-flywheel-integration}"

# Monitor service configuration
CHECK_INTERVAL="${BEAD_STALE_CHECK_INTERVAL:-60}"           # Check every 60 seconds
PID_FILE="${PIDS_DIR}/bead-stale-monitor.pid"
CONFIG_FILE="${PIDS_DIR}/bead-stale-monitor.conf"
MONITOR_LOG_FILE="${PIDS_DIR}/bead-stale-monitor.log"
NOTIFICATIONS_DIR="${PROJECT_DIR}/.beads/stale-notifications"

# Thresholds (seconds)
FIRST_REMINDER_THRESHOLD="${FIRST_REMINDER_THRESHOLD:-900}"  # 15 minutes
ESCALATION_THRESHOLD="${ESCALATION_THRESHOLD:-1800}"         # 30 minutes

# Ensure log file exists
mkdir -p "$(dirname "$MONITOR_LOG_FILE")"
touch "$MONITOR_LOG_FILE"

# Function to send SystemNotify
send_notify() {
    local agent="$1"
    local bead_id="$2"
    local message="$3"

    local subject="[System] ⏰ Stale bead reminder: $bead_id"
    local full_message="System notice (not sent by an agent): $message

Bead ID: $bead_id
Agent: $agent
Time: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

Suggested Actions:
1. If still working, commit changes with [bd-xxx] prefix to reset timer
2. If done, close the bead: br close $bead_id
3. If no longer needed, consider releasing for other agents

Project: $PROJECT_KEY"

    # Send via agent mail using SystemNotify sender identity
    MAIL_SENDER_NAME="SystemNotify" "$SCRIPT_DIR/agent-mail-helper.sh" send "$agent" "$subject" "$full_message" >/dev/null 2>&1 || true
    echo "Sent SystemNotify to $agent for bead $bead_id" >&2
}

# Function to get current timestamp in seconds since epoch (UTC)
current_timestamp() {
    date -u +%s
}

# Function to parse ISO timestamp to seconds since epoch (UTC)
iso_to_epoch() {
    local iso="$1"
    # Convert ISO 8601 to epoch (macOS/BSD compatible) in UTC
    date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null || \
    date -u -d "$iso" +%s 2>/dev/null || \
    echo "0"
}

# Function to get latest activity timestamp for a bead
get_latest_activity() {
    local bead_id="$1"

    # Use jq to filter entries for this bead_id with relevant actions
    # Actions that count as activity: claim, create, edit_allowed, commit
    # Sort by timestamp descending, get most recent
    local latest_iso
    latest_iso=$(jq -c --arg bid "$bead_id" \
        'select(.bead_id == $bid) |
         select(.action | IN("claim", "create", "edit_allowed", "commit")) |
         .timestamp' "$LOG_FILE" 2>/dev/null | tail -1)

    if [ -z "$latest_iso" ] || [ "$latest_iso" = "null" ]; then
        echo "0"
        return
    fi

    # Remove quotes
    latest_iso="${latest_iso%\"}"
    latest_iso="${latest_iso#\"}"
    iso_to_epoch "$latest_iso"
}

# Function to get last reminder timestamp for a bead
get_last_reminder() {
    local bead_id="$1"

    local latest_iso
    latest_iso=$(jq -c --arg bid "$bead_id" \
        'select(.bead_id == $bid) |
         select(.action == "reminder_sent") |
         .timestamp' "$LOG_FILE" 2>/dev/null | tail -1)

    if [ -z "$latest_iso" ] || [ "$latest_iso" = "null" ]; then
        echo "0"
        return
    fi

    # Remove quotes
    latest_iso="${latest_iso%\"}"
    latest_iso="${latest_iso#\"}"
    iso_to_epoch "$latest_iso"
}

# Function to get last idle-agent notification timestamp for an agent
get_last_idle_notification() {
    local agent="$1"

    local latest_iso
    latest_iso=$(jq -c --arg ag "$agent" \
        'select(.agent == $ag) |
         select(.action == "idle_notification_sent") |
         .timestamp' "$LOG_FILE" 2>/dev/null | tail -1)

    if [ -z "$latest_iso" ] || [ "$latest_iso" = "null" ]; then
        echo "0"
        return
    fi

    # Remove quotes
    latest_iso="${latest_iso%\"}"
    latest_iso="${latest_iso#\"}"
    iso_to_epoch "$latest_iso"
}

# Function to get active agents from tmux panes (current session only)
get_active_agents() {
    # Detect current tmux session
    local current_session
    if [ -n "${TMUX:-}" ]; then
        current_session=$(tmux display-message -p '#{session_name}' 2>/dev/null || echo "")
    else
        current_session=""
    fi

    # If we can detect the session, filter for that session only
    # Otherwise fall back to all sessions (for manual runs outside tmux)
    if [ -n "$current_session" ]; then
        tmux list-panes -t "$current_session" -F "#{@agent_name}" 2>/dev/null | grep -v '^$' | sort -u
    else
        # Fallback: try to guess session from project directory
        # Look for sessions with panes in PROJECT_DIR
        local matching_agents=$(tmux list-panes -a -F "#{pane_current_path} #{@agent_name}" 2>/dev/null | \
            awk -v project="$PROJECT_DIR" '$1 ~ project && $2 != "" {print $2}' | sort -u)

        if [ -n "$matching_agents" ]; then
            echo "$matching_agents"
        else
            # Last resort: all agents (backward compat)
            tmux list-panes -a -F "#{@agent_name}" 2>/dev/null | grep -v '^$' | sort -u
        fi
    fi
}

# Function to check if agent is idle (no active bead)
is_agent_idle() {
    local agent="$1"
    local tracking_file="/tmp/agent-bead-${agent}.txt"

    # Agent is idle if:
    # 1. No tracking file exists, OR
    # 2. Tracking file exists but is empty or contains no valid bead ID
    if [ ! -f "$tracking_file" ]; then
        return 0  # Idle
    fi

    local bead_id
    bead_id=$(cat "$tracking_file" 2>/dev/null | tr -d '[:space:]')

    if [ -z "$bead_id" ] || [ "$bead_id" = "null" ]; then
        return 0  # Idle
    fi

    return 1  # Busy
}

# Function to send idle-agent notification
send_idle_agent_notify() {
    local agent="$1"
    local available_count="$2"

    local subject="[System] 🎯 Beads available for work"
    local message="System notice: Work is available!

Available beads: $available_count
Status: You are currently idle

Action: Run 'bv --robot-next' to claim the next bead

Time: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Project: $PROJECT_KEY"

    # Send via agent mail using SystemNotify sender identity
    MAIL_SENDER_NAME="SystemNotify" "$PROJECT_ROOT/scripts/agent-mail-helper.sh" send "$agent" "$subject" "$message"
    echo "Sent idle-agent notification to $agent ($available_count beads available)" >&2
}

# Function to check for idle agents and notify if work available
check_idle_agents() {
    echo "Checking for idle agents..." >&2

    # Get all open beads (available work)
    local open_beads_json
    open_beads_json=$(br list --status open --json 2>/dev/null || echo "[]")
    local open_count
    open_count=$(echo "$open_beads_json" | jq -r 'length')

    if [ "$open_count" -eq 0 ]; then
        echo "No open beads available, skipping idle agent notifications" >&2
        return 0
    fi

    echo "Found $open_count open beads available for work" >&2

    # Get active agents
    local agents
    agents=$(get_active_agents)

    if [ -z "$agents" ]; then
        echo "No active agents found" >&2
        return 0
    fi

    local current_epoch
    current_epoch=$(current_timestamp)

    # Check each agent
    while IFS= read -r agent; do
        [ -z "$agent" ] && continue

        # Skip if agent is busy
        if ! is_agent_idle "$agent"; then
            echo "Agent $agent is busy (has active bead)" >&2
            continue
        fi

        # Agent is idle - check if we already notified recently
        local last_notification
        last_notification=$(get_last_idle_notification "$agent")
        local notification_seconds_ago=$((current_epoch - last_notification))

        # Don't spam - wait at least 5 minutes between idle notifications
        local IDLE_NOTIFICATION_COOLDOWN=300  # 5 minutes

        if [ "$last_notification" -ne 0 ] && [ $notification_seconds_ago -lt $IDLE_NOTIFICATION_COOLDOWN ]; then
            echo "Idle notification already sent to $agent ${notification_seconds_ago}s ago (cooldown: ${IDLE_NOTIFICATION_COOLDOWN}s)" >&2
            continue
        fi

        # Send notification
        echo "Agent $agent is idle and beads are available, sending notification" >&2
        send_idle_agent_notify "$agent" "$open_count"

        # Log notification sent
        if [ -f "$LOG_SCRIPT" ]; then
            # Log with agent field instead of bead_id for idle notifications
            echo "{\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"agent\":\"$agent\",\"action\":\"idle_notification_sent\",\"actor\":\"SystemNotify\"}" >> "$LOG_FILE"
        fi
    done <<< "$agents"
}

# Main monitoring function
monitor_beads() {
    echo "Checking for stale beads (threshold: ${FIRST_REMINDER_THRESHOLD}s)..." >&2

    # Get all in_progress beads
    local beads_json
    beads_json=$(br list --status in_progress --json 2>/dev/null || echo "[]")

    # Extract bead IDs and owners
    local bead_count
    bead_count=$(echo "$beads_json" | jq -r 'length')

    # Check for stale beads only if there are beads in progress
    if [ "$bead_count" -eq 0 ]; then
        echo "No beads in progress." >&2
    else
        echo "Found $bead_count beads in progress." >&2

        local current_epoch
        current_epoch=$(current_timestamp)

        # Process each bead
        for i in $(seq 0 $((bead_count - 1))); do
            local bead_id owner
            bead_id=$(echo "$beads_json" | jq -r ".[$i].id")
            owner=$(echo "$beads_json" | jq -r ".[$i].created_by")

            if [ -z "$bead_id" ] || [ "$bead_id" = "null" ]; then
                continue
            fi

            # Get latest activity
            local last_activity
            last_activity=$(get_latest_activity "$bead_id")

            if [ "$last_activity" -eq 0 ]; then
                # No activity logged, use bead creation time?
                echo "No activity logged for $bead_id, skipping." >&2
                continue
            fi

            # Calculate inactivity duration
            local inactive_seconds=$((current_epoch - last_activity))

            # Get last reminder time
            local last_reminder
            last_reminder=$(get_last_reminder "$bead_id")
            local reminder_seconds_ago=$((current_epoch - last_reminder))

            # Determine if reminder needed
            if [ $inactive_seconds -ge $FIRST_REMINDER_THRESHOLD ]; then
                # Check if we already sent a reminder recently (within threshold)
                if [ $reminder_seconds_ago -ge $FIRST_REMINDER_THRESHOLD ]; then
                    # Send reminder
                    local message
                    if [ $inactive_seconds -ge $ESCALATION_THRESHOLD ]; then
                        message="Bead $bead_id inactive for $((inactive_seconds / 60)) minutes. Consider closing or resuming work."
                    else
                        message="Still working on $bead_id? Last activity $((inactive_seconds / 60)) minutes ago."
                    fi

                    echo "Sending reminder for $bead_id (owner: $owner, inactive: ${inactive_seconds}s)" >&2
                    send_notify "$owner" "$bead_id" "$message"

                    # Log reminder sent
                    if [ -f "$LOG_SCRIPT" ]; then
                        "$LOG_SCRIPT" "$bead_id" "reminder_sent" "SystemNotify"
                    fi
                else
                    echo "Reminder already sent $reminder_seconds_ago seconds ago for $bead_id" >&2
                fi
            else
                echo "Bead $bead_id active ($inactive_seconds seconds ago)" >&2
            fi
        done
    fi

    # Always check for idle agents, regardless of whether there were stale beads
    check_idle_agents
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --interval) CHECK_INTERVAL="$2"; BEAD_STALE_CHECK_INTERVAL="$2"; shift 2 ;;
            --first-threshold) FIRST_REMINDER_THRESHOLD="$2"; shift 2 ;;
            --escalation-threshold) ESCALATION_THRESHOLD="$2"; shift 2 ;;
            --project) PROJECT_KEY="$2"; MAIL_PROJECT_KEY="$2"; shift 2 ;;
            *) break ;;
        esac
    done
}

# Save configuration to file
save_config() {
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cat > "$CONFIG_FILE" <<EOF
FIRST_REMINDER_THRESHOLD=$FIRST_REMINDER_THRESHOLD
ESCALATION_THRESHOLD=$ESCALATION_THRESHOLD
CHECK_INTERVAL=$CHECK_INTERVAL
PROJECT_KEY=$PROJECT_KEY
EOF
}

# Load configuration from file
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
}

# Start the monitor
start_monitor() {
    shift  # Remove 'start' from args
    parse_args "$@"

    # Save configuration for status reporting
    save_config

    # Check if already running
    if [ -f "$PID_FILE" ]; then
        local old_pid
        old_pid=$(cat "$PID_FILE")
        if ps -p "$old_pid" >/dev/null 2>&1; then
            echo "Monitor already running (PID: $old_pid)"
            return 0
        else
            # Stale PID file
            rm -f "$PID_FILE"
        fi
    fi

    # Ensure directories exist
    mkdir -p "$(dirname "$PID_FILE")"
    mkdir -p "$NOTIFICATIONS_DIR"

    echo "Starting bead stale monitor..."
    echo "Check interval: ${CHECK_INTERVAL}s"
    echo "First reminder threshold: ${FIRST_REMINDER_THRESHOLD}s (~$((FIRST_REMINDER_THRESHOLD / 60)) minutes)"
    echo "Escalation threshold: ${ESCALATION_THRESHOLD}s (~$((ESCALATION_THRESHOLD / 60)) minutes)"
    echo "Project: ${PROJECT_KEY}"

    # Start background monitor
    nohup bash -c '
      SCRIPT_PATH="$1"
      INTERVAL="$2"
      MONITOR_LOG="$3"
      while true; do
        "$SCRIPT_PATH" check >/dev/null 2>&1 || true
        sleep "$INTERVAL"
      done
    ' bash "$SCRIPT_DIR/bead-stale-monitor.sh" "$CHECK_INTERVAL" "$MONITOR_LOG_FILE" >>"$MONITOR_LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"

    local monitor_pid
    monitor_pid=$(cat "$PID_FILE")
    echo "✓ Monitor started (PID: $monitor_pid)"
    echo ""
    echo "To stop: $0 stop"
    echo "To check status: $0 status"
}

# Stop the monitor
stop_monitor() {
    if [ ! -f "$PID_FILE" ]; then
        echo "Monitor is not running"
        return 0
    fi

    local pid
    pid=$(cat "$PID_FILE")

    if ps -p "$pid" >/dev/null 2>&1; then
        echo "Stopping monitor (PID: $pid)..."
        kill "$pid" 2>/dev/null || true
        rm -f "$PID_FILE"
        echo "✓ Monitor stopped"
    else
        echo "Monitor not running (removing stale PID file)"
        rm -f "$PID_FILE"
    fi
}

# Check monitor status
check_status() {
    if [ ! -f "$PID_FILE" ]; then
        echo "✗ Monitor is not running"
        return 1
    fi

    local pid
    pid=$(cat "$PID_FILE")

    if ps -p "$pid" >/dev/null 2>&1; then
        # Load actual running configuration
        load_config

        echo "✓ Monitor is running (PID: $pid)"
        echo "Check interval: ${CHECK_INTERVAL}s"
        echo "First reminder threshold: ${FIRST_REMINDER_THRESHOLD}s (~$((FIRST_REMINDER_THRESHOLD / 60)) minutes)"
        echo "Escalation threshold: ${ESCALATION_THRESHOLD}s (~$((ESCALATION_THRESHOLD / 60)) minutes)"
        echo "Project: ${PROJECT_KEY}"
        return 0
    else
        echo "✗ Monitor not running (stale PID file)"
        rm -f "$PID_FILE"
        return 1
    fi
}

# Usage info
usage() {
    cat <<EOF
Bead Stale Monitor

Automatically sends SystemNotify reminders for beads inactive for 15+ minutes.

USAGE:
    $0 start [OPTIONS]    Start the background monitor
    $0 stop               Stop the monitor
    $0 status             Check if monitor is running
    $0 check              Manual check (used internally)
    $0                    Run a single check (legacy)

OPTIONS:
    --interval SECONDS     How often to check in seconds (default: 60)
    --first-threshold SEC  First reminder threshold in seconds (default: 900 = 15 min)
    --escalation-threshold SEC  Escalation threshold in seconds (default: 1800 = 30 min)
    --project PATH         Project key/path (default: auto-detected)

ENVIRONMENT:
    Set DISABLE_BEAD_STALE_MONITOR=1 to opt-out of monitoring

EXAMPLES:
    # Start with defaults (check every 60s)
    $0 start

    # Start with custom parameters (check every 30s)
    $0 start --interval 30 --first-threshold 600 --escalation-threshold 1200

    # Stop the monitor
    $0 stop

    # Check status
    $0 status

NOTE: Configuration is saved when starting and persisted across checks.
      Notifications are sent via SystemNotify sender identity.

EOF
}

# Main
main() {
    # Check for opt-out
    if [ "${DISABLE_BEAD_STALE_MONITOR:-0}" = "1" ]; then
        echo "Bead stale monitoring disabled (DISABLE_BEAD_STALE_MONITOR=1)"
        exit 0
    fi

    local action="${1:-}"

    case "$action" in
        start)
            start_monitor "$@"
            ;;
        stop)
            stop_monitor
            ;;
        status)
            check_status
            ;;
        check)
            # Internal command for periodic checks
            shift  # Remove 'check' from args
            parse_args "$@"
            monitor_beads
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            # Legacy behavior: run a single check
            parse_args "$@"
            monitor_beads
            ;;
    esac
}

# If script is called directly, run main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
