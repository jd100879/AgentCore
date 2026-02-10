#!/usr/bin/env bash
# Expiry Notification Monitor - Phase 3A
# Automatically sends mail notifications when reservations near expiry
# Usage: ./scripts/expiry-notify-monitor.sh [start|stop|status]

# Note: -e flag intentionally omitted for fault tolerance
# Monitor should keep running even if individual checks fail
set -uo pipefail

# Source shared project configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_FLYWHEEL_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib/project-config.sh"

# Configuration
MAIL_SERVER="${MAIL_SERVER:-http://127.0.0.1:8765}"
MCP_AGENT_MAIL_DIR="${MCP_AGENT_MAIL_DIR:-$HOME/mcp_agent_mail}"
TOKEN_FILE="$MCP_AGENT_MAIL_DIR/.env"
PROJECT_KEY="${PROJECT_KEY:-$MAIL_PROJECT_KEY}"
TTL_WARN_THRESHOLD="${TTL_WARN_THRESHOLD:-900}"  # 15 minutes default
CHECK_INTERVAL="${EXPIRY_CHECK_INTERVAL:-60}"     # Check every 60 seconds
NOTIFICATIONS_DIR="$AGENT_FLYWHEEL_ROOT/.expiry-notifications"
PID_FILE="$AGENT_FLYWHEEL_ROOT/pids/expiry-monitor.pid"
CONFIG_FILE="$AGENT_FLYWHEEL_ROOT/pids/expiry-monitor.conf"
LOG_FILE="$AGENT_FLYWHEEL_ROOT/pids/expiry-monitor.log"
# Monitor scope: when MONITOR_ALL_AGENTS=1, this process watches all reservations and
# notifies each holder. Set to 0 to only watch the current agent's reservations.
MONITOR_ALL_AGENTS="${MONITOR_ALL_AGENTS:-1}"
# Sender identity for notifications (must be registered server-side)
MAIL_SENDER_NAME="${MAIL_SENDER_NAME:-SystemNotify}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Get agent name
get_agent_name() {
    local agent_name
    agent_name=$("$SCRIPT_DIR/agent-mail-helper.sh" whoami 2>/dev/null || echo "")
    if [ -z "$agent_name" ] || [ "$agent_name" = "unknown" ]; then
        echo ""
        return 1
    fi
    echo "$agent_name"
}

# Defaults (overridable by flags/env)
DEFAULT_TTL_WARN_THRESHOLD="${TTL_WARN_THRESHOLD:-900}"
DEFAULT_CHECK_INTERVAL="${EXPIRY_CHECK_INTERVAL:-60}"
DEFAULT_MONITOR_ALL_AGENTS="${MONITOR_ALL_AGENTS:-1}"
DEFAULT_SENDER="${MAIL_SENDER_NAME:-SystemNotify}"
DEFAULT_PROJECT_KEY="${PROJECT_KEY:-$MAIL_PROJECT_KEY}"

# Make MCP resource call
mcp_resource() {
    local uri=$1

    if [ ! -f "$TOKEN_FILE" ]; then
        return 1
    fi

    local token
    token=$(grep HTTP_BEARER_TOKEN "$TOKEN_FILE" | cut -d'=' -f2)

    local payload=$(cat <<EOF
{
  "jsonrpc": "2.0",
  "method": "resources/read",
  "params": {
    "uri": "$uri"
  },
  "id": $(date +%s)
}
EOF
)

    curl -s -X POST "$MAIL_SERVER/mcp" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$payload"
}

# Check if a notification was already sent for this reservation
notification_sent() {
    local agent=$1
    local reservation_id=$2
    local expires_ts=$3

    mkdir -p "$NOTIFICATIONS_DIR"

    # Notification key: agent_id_expires (to detect renewals)
    local notif_file="$NOTIFICATIONS_DIR/${agent}_${reservation_id}_${expires_ts}.sent"

    [ -f "$notif_file" ]
}

# Mark notification as sent
mark_notification_sent() {
    local agent=$1
    local reservation_id=$2
    local expires_ts=$3

    mkdir -p "$NOTIFICATIONS_DIR"

    local notif_file="$NOTIFICATIONS_DIR/${agent}_${reservation_id}_${expires_ts}.sent"
    touch "$notif_file"
}

# Clean old notification markers (older than 24h)
cleanup_old_notifications() {
    mkdir -p "$NOTIFICATIONS_DIR"

    # Cross-platform: find files older than 24 hours and delete
    find "$NOTIFICATIONS_DIR" -name "*.sent" -type f -mtime +1 -delete 2>/dev/null || true
}

# Check and notify for expiring reservations
check_expiring_reservations() {
    local agent
    agent=$(get_agent_name) || return 0

    [ -z "$agent" ] && return 0

    # Convert project key to slug
    local slug
    slug=$(echo "$PROJECT_KEY" | sed 's/^\/\+//' | tr '/' '-' | tr '[:upper:]' '[:lower:]')

    # Get all active reservations
    local response
    response=$(mcp_resource "resource://file_reservations/$slug?active_only=true") || return 0

    local reservations
    reservations=$(echo "$response" | jq -r '.result.contents[0].text' 2>/dev/null) || return 0

    if [ -z "$reservations" ] || [ "$reservations" = "null" ] || [ "$reservations" = "[]" ]; then
        return 0
    fi

    local now
    now=$(date -u +%s)

    # Check each reservation for this agent
    echo "$reservations" | jq -c '.[]' | while read -r item; do
        local holder expires_ts path_pattern reservation_id
        holder=$(echo "$item" | jq -r '.agent')
        expires_ts=$(echo "$item" | jq -r '.expires_ts')
        path_pattern=$(echo "$item" | jq -r '.path_pattern')
        reservation_id=$(echo "$item" | jq -r '.id')

        # Scope: either all agents or just the current agent
        if [ "$MONITOR_ALL_AGENTS" != "1" ] && [ "$holder" != "$agent" ]; then
            continue
        fi

        # Parse expiry timestamp (cross-platform)
        # Remove microseconds and normalize timezone format for BSD date
        local expires_normalized
        expires_normalized=$(echo "$expires_ts" | sed 's/\.[0-9]\{1,\}+/+/' | sed 's/+\([0-9][0-9]\):\([0-9][0-9]\)$/+\1\2/')

        local exp_epoch
        # Try GNU date (Linux/WSL) - handles original format
        exp_epoch=$(date -d "$expires_ts" +%s 2>/dev/null || \
                    # Try BSD date (macOS) - needs normalized format
                    date -j -f "%Y-%m-%dT%H:%M:%S%z" "$expires_normalized" +%s 2>/dev/null || \
                    echo "")

        [ -z "$exp_epoch" ] && continue

        # Calculate time until expiry
        local time_until_expiry=$((exp_epoch - now))

        # Check if within warning threshold and not expired yet
        if [ "$time_until_expiry" -le "$TTL_WARN_THRESHOLD" ] && [ "$time_until_expiry" -gt 0 ]; then
            # Check if already notified
            if ! notification_sent "$holder" "$reservation_id" "$expires_ts"; then
                # Send notification
                send_expiry_notification "$holder" "$reservation_id" "$path_pattern" "$expires_ts" "$time_until_expiry"

                # Mark as sent
                mark_notification_sent "$holder" "$reservation_id" "$expires_ts"
            fi
        fi
    done
}

# Send expiry notification mail
send_expiry_notification() {
    local agent=$1
    local reservation_id=$2
    local path_pattern=$3
    local expires_ts=$4
    local time_until_expiry=$5

    local minutes=$((time_until_expiry / 60))

    local subject="[System] ⏰ Reservation expiring soon (ID: $reservation_id)"

    # Use configured sender identity (defaults to SystemNotify, enforced - no fallback)
    local sender_name="$MAIL_SENDER_NAME"

    local message="System notice (not sent by an agent): your file reservation is expiring soon.

Reservation Details:
- Path: $path_pattern
- Reservation ID: $reservation_id
- Expires at: $expires_ts
- Time remaining: ~${minutes} minutes

Suggested Actions:
1. Renew if you still need it: ./scripts/reserve-files.sh renew
2. Release if you're done: ./scripts/reserve-files.sh release --id $reservation_id
3. Do nothing - it will expire automatically

Project: $PROJECT_KEY"

    # Send via agent mail using system sender identity (must be registered server-side)
    # Fail loudly if send fails - log to monitor log file
    local send_result
    send_result=$(MAIL_SENDER_NAME="$sender_name" "$SCRIPT_DIR/agent-mail-helper.sh" send "$agent" "$subject" "$message" 2>&1)
    local send_status=$?

    if [ $send_status -ne 0 ]; then
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ERROR: Failed to send expiry notification as $sender_name to $agent: $send_result" >> "$LOG_FILE"
        return 1
    fi

    # Check if sender was auto-renamed (would appear in output)
    if echo "$send_result" | grep -qi "auto-renamed\|rejected\|unauthorized\|unknown sender"; then
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ERROR: Sender $sender_name not recognized by server. Output: $send_result" >> "$LOG_FILE"
        return 1
    fi
}

# Parse args for check/start
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --warn) TTL_WARN_THRESHOLD="$2"; shift 2 ;;
            --interval) CHECK_INTERVAL="$2"; EXPIRY_CHECK_INTERVAL="$2"; shift 2 ;;
            --sender) MAIL_SENDER_NAME="$2"; shift 2 ;;
            --project) PROJECT_KEY="$2"; MAIL_PROJECT_KEY="$2"; shift 2 ;;
            --monitor-all) MONITOR_ALL_AGENTS=1; shift ;;
            --monitor-self) MONITOR_ALL_AGENTS=0; shift ;;
            *) break ;;
        esac
    done
    # Fallbacks
    TTL_WARN_THRESHOLD="${TTL_WARN_THRESHOLD:-$DEFAULT_TTL_WARN_THRESHOLD}"
    CHECK_INTERVAL="${CHECK_INTERVAL:-$DEFAULT_CHECK_INTERVAL}"
    EXPIRY_CHECK_INTERVAL="${EXPIRY_CHECK_INTERVAL:-$CHECK_INTERVAL}"
    MONITOR_ALL_AGENTS="${MONITOR_ALL_AGENTS:-$DEFAULT_MONITOR_ALL_AGENTS}"
    MAIL_SENDER_NAME="${MAIL_SENDER_NAME:-$DEFAULT_SENDER}"
    PROJECT_KEY="${PROJECT_KEY:-$DEFAULT_PROJECT_KEY}"
    MAIL_PROJECT_KEY="${MAIL_PROJECT_KEY:-$PROJECT_KEY}"
}

# Save configuration to file
save_config() {
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cat > "$CONFIG_FILE" <<EOF
TTL_WARN_THRESHOLD=$TTL_WARN_THRESHOLD
CHECK_INTERVAL=$CHECK_INTERVAL
MAIL_SENDER_NAME=$MAIL_SENDER_NAME
PROJECT_KEY=$PROJECT_KEY
MONITOR_ALL_AGENTS=$MONITOR_ALL_AGENTS
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
            echo -e "${YELLOW}Monitor already running (PID: $old_pid)${NC}"
            return 0
        else
            # Stale PID file
            rm -f "$PID_FILE"
        fi
    fi

    # Ensure directories exist
    mkdir -p "$(dirname "$PID_FILE")"
    mkdir -p "$NOTIFICATIONS_DIR"

    echo -e "${GREEN}Starting expiry notification monitor...${NC}"
    echo "Check interval: ${CHECK_INTERVAL}s"
    echo "Warning threshold: ${TTL_WARN_THRESHOLD}s (~$((TTL_WARN_THRESHOLD / 60)) minutes)"
    echo "Sender identity: ${MAIL_SENDER_NAME}"
    echo "Monitor scope: $([ "$MONITOR_ALL_AGENTS" = "1" ] && echo "all agents" || echo "self only")"
    echo "Project: ${PROJECT_KEY}"

    # Start background monitor (pass explicit args; no env reliance)
    local scope_flag
    if [ "$MONITOR_ALL_AGENTS" = "1" ]; then scope_flag="--monitor-all"; else scope_flag="--monitor-self"; fi

    # Simple, robust background loop (avoid setsid/pty issues on macOS)
    nohup bash -c '
      SCRIPT_PATH="$1"
      WARN="$2"
      INTERVAL="$3"
      SENDER="$4"
      PROJECT="$5"
      SCOPE_FLAG="$6"
      NOTIF_DIR="$7"
      LOG_FILE="$8"
      while true; do
        "$SCRIPT_PATH" check --warn "$WARN" --interval "$INTERVAL" --sender "$SENDER" --project "$PROJECT" $SCOPE_FLAG >/dev/null 2>&1 || true
        find "$NOTIF_DIR" -name "*.sent" -type f -mtime +1 -delete 2>/dev/null || true
        sleep "$INTERVAL"
      done
    ' bash "$SCRIPT_DIR/expiry-notify-monitor.sh" "$TTL_WARN_THRESHOLD" "$CHECK_INTERVAL" "$MAIL_SENDER_NAME" "$PROJECT_KEY" "$scope_flag" "$NOTIFICATIONS_DIR" "$LOG_FILE" >>"$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"

    local monitor_pid
    monitor_pid=$(cat "$PID_FILE")

    echo -e "${GREEN}✓ Monitor started (PID: $monitor_pid)${NC}"
    echo ""
    echo "To stop: $0 stop"
    echo "To check status: $0 status"
}

# Stop the monitor
stop_monitor() {
    if [ ! -f "$PID_FILE" ]; then
        echo -e "${YELLOW}Monitor is not running${NC}"
        return 0
    fi

    local pid
    pid=$(cat "$PID_FILE")

    if ps -p "$pid" >/dev/null 2>&1; then
        echo "Stopping monitor (PID: $pid)..."
        kill "$pid" 2>/dev/null || true
        rm -f "$PID_FILE"
        echo -e "${GREEN}✓ Monitor stopped${NC}"
    else
        echo -e "${YELLOW}Monitor not running (removing stale PID file)${NC}"
        rm -f "$PID_FILE"
    fi
}

# Check monitor status
check_status() {
    if [ ! -f "$PID_FILE" ]; then
        echo -e "${RED}✗ Monitor is not running${NC}"
        return 1
    fi

    local pid
    pid=$(cat "$PID_FILE")

    if ps -p "$pid" >/dev/null 2>&1; then
        # Load actual running configuration
        load_config

        echo -e "${GREEN}✓ Monitor is running (PID: $pid)${NC}"
        echo "Check interval: ${CHECK_INTERVAL}s"
        echo "Warning threshold: ${TTL_WARN_THRESHOLD}s (~$((TTL_WARN_THRESHOLD / 60)) minutes)"
        echo "Sender identity: ${MAIL_SENDER_NAME}"
        echo "Monitor scope: $([ "$MONITOR_ALL_AGENTS" = "1" ] && echo "all agents" || echo "self only")"
        echo "Project: ${PROJECT_KEY}"

        # Show notification count
        local notif_count
        notif_count=$(find "$NOTIFICATIONS_DIR" -name "*.sent" -type f 2>/dev/null | wc -l | xargs)
        echo "Notifications sent (24h): $notif_count"

        return 0
    else
        echo -e "${RED}✗ Monitor not running (stale PID file)${NC}"
        rm -f "$PID_FILE"
        return 1
    fi
}

# Usage info
usage() {
    cat <<EOF
Expiry Notification Monitor - Phase 3A

Automatically sends mail notifications when reservations near expiry.

USAGE:
    $0 start [OPTIONS]    Start the background monitor
    $0 stop               Stop the monitor
    $0 status             Check if monitor is running
    $0 check [OPTIONS]    Manual check (used internally)

OPTIONS:
    --warn SECONDS         Warning threshold in seconds (default: 900 = 15 min)
    --interval SECONDS     How often to check in seconds (default: 60)
    --sender NAME          Sender identity for notifications (default: SystemNotify)
    --project PATH         Project key/path (default: auto-detected)
    --monitor-all          Monitor all agents' reservations (default)
    --monitor-self         Only monitor current agent's reservations

ENVIRONMENT:
    Set DISABLE_EXPIRY_NOTIFY=1 to opt-out of notifications

EXAMPLES:
    # Start with defaults (15 min warning, check every 60s)
    $0 start

    # Start with custom parameters (15s warning, check every 3s)
    $0 start --warn 15 --interval 3 --sender SystemNotify --monitor-all

    # Stop the monitor
    $0 stop

    # Check status (shows actual running configuration)
    $0 status

NOTE: Configuration is saved when starting and persisted across checks.
      Notifications are sent via agent mail system.

EOF
}

# Main
main() {
    # Check for opt-out
    if [ "${DISABLE_EXPIRY_NOTIFY:-0}" = "1" ]; then
        echo -e "${YELLOW}Expiry notifications disabled (DISABLE_EXPIRY_NOTIFY=1)${NC}"
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
            # Internal command for periodic checks - parse args
            shift  # Remove 'check' from args
            parse_args "$@"
            check_expiring_reservations
            ;;
        help|--help|-h|"")
            usage
            ;;
        *)
            echo -e "${RED}Unknown action: $action${NC}"
            usage
            exit 1
            ;;
    esac
}

main "$@"
