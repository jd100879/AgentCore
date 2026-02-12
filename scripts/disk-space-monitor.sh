#!/usr/bin/env bash
# Disk Space Monitor
# Automatically sends SystemNotify alerts when disk space falls below threshold
# Usage: ./scripts/disk-space-monitor.sh [start|stop|status]

# Note: -e flag intentionally omitted for fault tolerance
# Monitor should keep running even if individual checks fail
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
DISK_THRESHOLD_GB="${DISK_THRESHOLD_GB:-5}"           # Alert when under 5GB by default
CHECK_INTERVAL="${DISK_CHECK_INTERVAL:-300}"          # Check every 5 minutes
CRITICAL_THRESHOLD_GB="${CRITICAL_THRESHOLD_GB:-2}"   # Critical alert under 2GB
PID_FILE="$PROJECT_ROOT/pids/disk-monitor.pid"
NOTIFICATIONS_DIR="$PROJECT_ROOT/.disk-notifications"
LOG_FILE="$PROJECT_ROOT/pids/disk-monitor.log"
MAIL_SENDER_NAME="SystemNotify"

# Set project key for agent queries if not already set
export MAIL_PROJECT_KEY="${MAIL_PROJECT_KEY:-$PROJECT_ROOT}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Ensure pids directory exists
mkdir -p "$PROJECT_ROOT/pids"
mkdir -p "$NOTIFICATIONS_DIR"

# Get disk space in GB for a path
get_disk_space_gb() {
    local path="${1:-$HOME}"
    # Use df -k for consistency across platforms, convert to GB
    df -k "$path" 2>/dev/null | awk 'NR==2 {printf "%.2f", $4/1024/1024}'
}

# Get used percentage
get_disk_usage_percent() {
    local path="${1:-$HOME}"
    df -k "$path" 2>/dev/null | awk 'NR==2 {print int($5)}'
}

# Check if notification was recently sent (within last hour)
notification_recently_sent() {
    local level=$1
    local notif_file="$NOTIFICATIONS_DIR/last-${level}-alert.ts"

    if [ ! -f "$notif_file" ]; then
        return 1
    fi

    local last_ts=$(cat "$notif_file")
    local now_ts=$(date +%s)
    local diff=$((now_ts - last_ts))

    # Don't re-notify within 1 hour (3600 seconds)
    [ $diff -lt 3600 ]
}

# Mark notification as sent
mark_notification_sent() {
    local level=$1
    local notif_file="$NOTIFICATIONS_DIR/last-${level}-alert.ts"
    date +%s > "$notif_file"
}

# Send notification to all active agents
send_notification() {
    local subject=$1
    local message=$2
    local level=${3:-warning}

    # Check if already notified recently
    if notification_recently_sent "$level"; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Skipping $level notification (already sent within last hour)" >> "$LOG_FILE"
        return 0
    fi
    echo "[DEBUG] MAIL_PROJECT_KEY=$MAIL_PROJECT_KEY" >> "$LOG_FILE"

    echo "[DEBUG] SCRIPT_DIR=$SCRIPT_DIR" >> "$LOG_FILE"
    # Get list of active agents
    local agents=$("$SCRIPT_DIR/agent-mail-helper.sh" list --active 2>/dev/null | awk '{print $1}')
    echo "[DEBUG] Agent list command output:" >> "$LOG_FILE"
    "$SCRIPT_DIR/agent-mail-helper.sh" list --active 2>/dev/null >> "$LOG_FILE"
    echo "[DEBUG] Parsed agents: [$agents]" >> "$LOG_FILE"

    if [ -z "$agents" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] No active agents to notify" >> "$LOG_FILE"
        return 0
    fi

    # Send to each active agent
    local notified_count=0
    while read -r agent; do
        [ -z "$agent" ] && continue

        if MAIL_SENDER_NAME="$MAIL_SENDER_NAME" "$SCRIPT_DIR/agent-mail-helper.sh" send "$agent" "$subject" "$message" 2>/dev/null; then
            ((notified_count++))
        fi
    done <<< "$agents"

    if [ $notified_count -gt 0 ]; then
        mark_notification_sent "$level"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] Notified $notified_count agents: $subject" >> "$LOG_FILE"
    fi
}

# Check disk space and send alerts if needed
check_disk_space() {
    local target_path="$HOME/.claude"
    local available_gb=$(get_disk_space_gb "$target_path")
    local used_percent=$(get_disk_usage_percent "$target_path")

    # Parse available space (handle decimal)
    local available_int=$(echo "$available_gb" | awk '{print int($1)}')

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Disk check: ${available_gb}GB available (${used_percent}% used)" >> "$LOG_FILE"

    # Critical alert (under 2GB)
    if [ "$available_int" -lt "$CRITICAL_THRESHOLD_GB" ]; then
        local message="⚠️  CRITICAL: Only ${available_gb}GB disk space remaining (${used_percent}% used)

Immediate action required to prevent agent failures!

Recommended cleanup:
  1. Old debug files: ~/.claude/debug/
  2. Old sessions: ~/.claude/projects/
  3. File history: ~/.claude/file-history/

See AgentCore disk cleanup documentation for safe cleanup procedures."

        send_notification "🚨 CRITICAL: Disk space very low" "$message" "critical"
        return 0
    fi

    # Warning alert (under 5GB)
    if [ "$available_int" -lt "$DISK_THRESHOLD_GB" ]; then
        local message="⚠️  WARNING: Disk space running low (${available_gb}GB available, ${used_percent}% used)

Consider cleaning up old files:
  - Debug files: ~/.claude/debug/
  - Old sessions: ~/.claude/projects/
  - File history: ~/.claude/file-history/

Current thresholds:
  Warning: ${DISK_THRESHOLD_GB}GB
  Critical: ${CRITICAL_THRESHOLD_GB}GB"

        send_notification "⚠️  Low disk space warning" "$message" "warning"
        return 0
    fi
}

# Monitor loop
monitor_loop() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Disk space monitor started (checking every ${CHECK_INTERVAL}s)" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Thresholds: Warning=${DISK_THRESHOLD_GB}GB, Critical=${CRITICAL_THRESHOLD_GB}GB" >> "$LOG_FILE"

    while true; do
        check_disk_space
        sleep "$CHECK_INTERVAL"
    done
}

# Start monitor
start_monitor() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo -e "${YELLOW}Disk space monitor already running (PID: $pid)${NC}"
            return 0
        else
            rm -f "$PID_FILE"
        fi
    fi

    # Start monitor in background
    monitor_loop >> "$LOG_FILE" 2>&1 &
    local pid=$!
    echo "$pid" > "$PID_FILE"

    echo -e "${GREEN}✓ Disk space monitor started (PID: $pid)${NC}"
    echo -e "  Threshold: ${DISK_THRESHOLD_GB}GB (warning), ${CRITICAL_THRESHOLD_GB}GB (critical)"
    echo -e "  Check interval: ${CHECK_INTERVAL}s"
    echo -e "  Log: $LOG_FILE"
}

# Stop monitor
stop_monitor() {
    if [ ! -f "$PID_FILE" ]; then
        echo -e "${YELLOW}Disk space monitor not running${NC}"
        return 0
    fi

    local pid=$(cat "$PID_FILE")
    if ps -p "$pid" > /dev/null 2>&1; then
        kill "$pid" 2>/dev/null
        rm -f "$PID_FILE"
        echo -e "${GREEN}✓ Disk space monitor stopped${NC}"
    else
        rm -f "$PID_FILE"
        echo -e "${YELLOW}Disk space monitor not running (stale PID file removed)${NC}"
    fi
}

# Show status
show_status() {
    local available_gb=$(get_disk_space_gb "$HOME/.claude")
    local used_percent=$(get_disk_usage_percent "$HOME/.claude")

    echo -e "${GREEN}Disk Space Monitor Status${NC}"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo -e "  Status: ${GREEN}Running${NC} (PID: $pid)"
        else
            echo -e "  Status: ${RED}Stopped${NC} (stale PID file)"
        fi
    else
        echo -e "  Status: ${RED}Stopped${NC}"
    fi

    echo -e "  Thresholds: ${DISK_THRESHOLD_GB}GB (warning), ${CRITICAL_THRESHOLD_GB}GB (critical)"
    echo -e "  Check interval: ${CHECK_INTERVAL}s"
    echo ""
    echo -e "${GREEN}Current Disk Usage${NC}"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  Available: ${available_gb}GB"
    echo -e "  Used: ${used_percent}%"

    # Color code the status
    local available_int=$(echo "$available_gb" | awk '{print int($1)}')
    if [ "$available_int" -lt "$CRITICAL_THRESHOLD_GB" ]; then
        echo -e "  Alert level: ${RED}🚨 CRITICAL${NC}"
    elif [ "$available_int" -lt "$DISK_THRESHOLD_GB" ]; then
        echo -e "  Alert level: ${YELLOW}⚠️  WARNING${NC}"
    else
        echo -e "  Alert level: ${GREEN}✓ OK${NC}"
    fi

    if [ -f "$LOG_FILE" ]; then
        echo ""
        echo -e "${GREEN}Recent log entries:${NC}"
        tail -5 "$LOG_FILE" 2>/dev/null | sed 's/^/  /'
    fi
}

# Main command dispatcher
case "${1:-status}" in
    start)
        start_monitor
        ;;
    stop)
        stop_monitor
        ;;
    status)
        show_status
        ;;
    check)
        check_disk_space
        echo "Check complete. See log: $LOG_FILE"
        ;;
    *)
        echo "Usage: $0 {start|stop|status|check}"
        exit 1
        ;;
esac
