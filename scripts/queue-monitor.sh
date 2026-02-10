#!/usr/bin/env bash
# queue-monitor.sh - Queue Monitor Daemon for NTM
#
# Watches task queue depth and triggers notifications when thresholds are breached.
# Part of bd-10w: Queue Monitor Daemon (Phase 1 NTM Implementation)
#
# Usage:
#   ./scripts/queue-monitor.sh start   # Start daemon in tmux session
#   ./scripts/queue-monitor.sh stop    # Stop daemon
#   ./scripts/queue-monitor.sh status  # Check daemon status
#   ./scripts/queue-monitor.sh attach  # Attach to daemon session

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SESSION_NAME="queue-monitor"
THRESHOLDS_FILE="$PROJECT_ROOT/.beads/queue-thresholds.conf"
EVENTS_LOG="$PROJECT_ROOT/.beads/queue-events.jsonl"
HEARTBEAT_LOG="$PROJECT_ROOT/.beads/agent-heartbeats.jsonl"
PID_FILE="$PROJECT_ROOT/pids/queue-monitor.pid"
CHECK_INTERVAL=30  # seconds

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_msg() {
    local color="${!1}"
    local msg="$2"
    echo -e "${color}${msg}${NC}" >&2
}

#######################################
# Initialize configuration file
#######################################
init_config() {
    if [ ! -f "$THRESHOLDS_FILE" ]; then
        mkdir -p "$(dirname "$THRESHOLDS_FILE")"
        cat > "$THRESHOLDS_FILE" <<'EOF'
# Queue Monitor Thresholds Configuration
# Format: threshold_name=value

# Queue depth thresholds (number of ready tasks)
QUEUE_DEPTH_LOW=5
QUEUE_DEPTH_MEDIUM=10
QUEUE_DEPTH_HIGH=20
QUEUE_DEPTH_CRITICAL=30

# Notification settings
NOTIFY_COORDINATORS=true

# Coordinator broadcast recipient (Phase 1 simple approach)
# Future: bd-1no will provide @coordinators group channels
COORDINATOR_RECIPIENT=Coordinators

# Check interval (seconds)
CHECK_INTERVAL=30

# Agent health monitoring settings (bd-13b)
HEALTH_CHECK_ENABLED=true
STUCK_TASK_THRESHOLD=7200    # 2 hours in seconds
HUNG_AGENT_THRESHOLD=1800    # 30 minutes in seconds
HEALTH_CHECK_INTERVAL=60     # Check agent health every 60 seconds
EOF
        print_msg GREEN "Created default configuration: $THRESHOLDS_FILE"
    fi
}

#######################################
# Load configuration
#######################################
load_config() {
    if [ -f "$THRESHOLDS_FILE" ]; then
        # Source config file to load variables
        # shellcheck disable=SC1090
        source "$THRESHOLDS_FILE"
    else
        # Use defaults
        QUEUE_DEPTH_LOW=5
        QUEUE_DEPTH_MEDIUM=10
        QUEUE_DEPTH_HIGH=20
        QUEUE_DEPTH_CRITICAL=30
        NOTIFY_COORDINATORS=true
        COORDINATOR_RECIPIENT="Coordinators"
    fi
}

#######################################
# Get current queue depth
# Returns: Number of ready tasks
#######################################
get_queue_depth() {
    local ready_output
    ready_output=$(br ready 2>/dev/null || echo "")

    if [ -z "$ready_output" ]; then
        echo "0"
        return
    fi

    # Count number of task lines (format: "● bd-XXX · Title [...]")
    echo "$ready_output" | grep -c "^[0-9]*\." || echo "0"
}

#######################################
# Determine threshold level
# Arguments:
#   $1 - Queue depth
# Returns: Level name (normal, low, medium, high, critical)
#######################################
get_threshold_level() {
    local depth=$1

    if [ "$depth" -ge "${QUEUE_DEPTH_CRITICAL:-30}" ]; then
        echo "critical"
    elif [ "$depth" -ge "${QUEUE_DEPTH_HIGH:-20}" ]; then
        echo "high"
    elif [ "$depth" -ge "${QUEUE_DEPTH_MEDIUM:-10}" ]; then
        echo "medium"
    elif [ "$depth" -ge "${QUEUE_DEPTH_LOW:-5}" ]; then
        echo "low"
    else
        echo "normal"
    fi
}

#######################################
# Log event to JSONL file
# Arguments:
#   $1 - Queue depth
#   $2 - Threshold level
#   $3 - Event type (threshold_breach, recovered, etc.)
#######################################
log_event() {
    local depth=$1
    local level=$2
    local event_type=$3
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    mkdir -p "$(dirname "$EVENTS_LOG")"

    # Create JSONL entry
    cat >> "$EVENTS_LOG" <<EOF
{"timestamp":"$timestamp","queue_depth":$depth,"level":"$level","event":"$event_type","monitor":"queue-monitor"}
EOF
}

#######################################
# Send notification via agent mail
# Arguments:
#   $1 - Queue depth
#   $2 - Threshold level
#######################################
send_notification() {
    local depth=$1
    local level=$2
    local agent_name

    # Get current agent name (if available)
    agent_name=$("$SCRIPT_DIR/agent-mail-helper.sh" whoami 2>/dev/null || echo "QueueMonitor")

    # Create notification message
    local subject="[queue-monitor] $level threshold reached: $depth ready tasks"
    local body="Queue Monitor Alert

Current queue depth: $depth ready tasks
Threshold level: $level

Thresholds:
  Low: ${QUEUE_DEPTH_LOW:-5}
  Medium: ${QUEUE_DEPTH_MEDIUM:-10}
  High: ${QUEUE_DEPTH_HIGH:-20}
  Critical: ${QUEUE_DEPTH_CRITICAL:-30}

Recommended actions:
  - Review ready tasks: br ready
  - Consider spawning additional agents
  - Check for blocked tasks: br list --status blocked

Event logged to: .beads/queue-events.jsonl

—Queue Monitor Daemon"

    # Send to coordinators (broadcast approach)
    if [ "${NOTIFY_COORDINATORS:-true}" = "true" ]; then
        local recipient="${COORDINATOR_RECIPIENT:-Coordinators}"
        "$SCRIPT_DIR/agent-mail-helper.sh" send "$recipient" "$subject" "$body" "queue-alerts" 2>/dev/null || true
        print_msg GREEN "Notification sent to $recipient"
    fi
}

#######################################
# Update agent heartbeat
# Arguments:
#   $1 - Agent name
#   $2 - Activity type (task_update, git_commit, file_modified)
#######################################
update_heartbeat() {
    local agent_name=$1
    local activity_type=${2:-"periodic_check"}
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    mkdir -p "$(dirname "$HEARTBEAT_LOG")"

    # Append heartbeat entry
    cat >> "$HEARTBEAT_LOG" <<EOF
{"timestamp":"$timestamp","agent":"$agent_name","activity":"$activity_type","monitor":"queue-monitor"}
EOF
}

#######################################
# Get active agents (agents with assigned tasks)
# Returns: List of agent names
#######################################
get_active_agents() {
    local agents
    agents=$(br list --status open 2>/dev/null | grep "Owner:" | sed 's/.*Owner: //' | sort -u)
    echo "$agents"
}

#######################################
# Get last heartbeat for an agent
# Arguments:
#   $1 - Agent name
# Returns: Timestamp of last heartbeat (or empty if none)
#######################################
get_last_heartbeat() {
    local agent_name=$1

    if [ ! -f "$HEARTBEAT_LOG" ]; then
        echo ""
        return
    fi

    # Get most recent heartbeat for this agent
    grep "\"agent\":\"$agent_name\"" "$HEARTBEAT_LOG" 2>/dev/null | tail -1 | jq -r '.timestamp' 2>/dev/null || echo ""
}

#######################################
# Check for stuck tasks (>2hr no updates)
# Returns: List of stuck task IDs
#######################################
check_stuck_tasks() {
    local threshold=${STUCK_TASK_THRESHOLD:-7200}  # 2 hours default
    local current_time
    current_time=$(date +%s)
    local stuck_tasks=""

    # Get all in-progress tasks
    local in_progress_tasks
    in_progress_tasks=$(br list --status open 2>/dev/null | grep "IN_PROGRESS" | grep -o 'bd-[a-z0-9]*' || echo "")

    if [ -z "$in_progress_tasks" ]; then
        echo ""
        return
    fi

    # Check each task's last update time
    while IFS= read -r task_id; do
        if [ -n "$task_id" ]; then
            # Get task details to find last update time
            local task_info
            task_info=$(br show "$task_id" 2>/dev/null || echo "")

            if [ -n "$task_info" ]; then
                # Extract "Updated:" timestamp
                local updated_line
                updated_line=$(echo "$task_info" | grep "Updated:" || echo "")

                if [ -n "$updated_line" ]; then
                    # Parse timestamp (format: "Updated: 2026-02-01")
                    local updated_date
                    updated_date=$(echo "$updated_line" | sed 's/.*Updated: //' | awk '{print $1}')

                    # Convert to seconds (simplified: assume today if within 24h)
                    local updated_time
                    updated_time=$(date -d "$updated_date" +%s 2>/dev/null || echo "$current_time")

                    local elapsed=$((current_time - updated_time))

                    if [ $elapsed -gt $threshold ]; then
                        stuck_tasks="$stuck_tasks $task_id"
                    fi
                fi
            fi
        fi
    done <<< "$in_progress_tasks"

    echo "$stuck_tasks" | xargs
}

#######################################
# Check for hung agents (>30min no heartbeat)
# Returns: List of hung agent names
#######################################
check_hung_agents() {
    local threshold=${HUNG_AGENT_THRESHOLD:-1800}  # 30 minutes default
    local current_time
    current_time=$(date +%s)
    local hung_agents=""

    # Get all active agents
    local agents
    agents=$(get_active_agents)

    if [ -z "$agents" ]; then
        echo ""
        return
    fi

    # Check each agent's last heartbeat
    while IFS= read -r agent_name; do
        if [ -n "$agent_name" ]; then
            local last_hb
            last_hb=$(get_last_heartbeat "$agent_name")

            if [ -z "$last_hb" ]; then
                # No heartbeat recorded yet, update one now
                update_heartbeat "$agent_name" "initial"
            else
                # Check if heartbeat is stale
                local hb_time
                hb_time=$(date -d "$last_hb" +%s 2>/dev/null || echo "$current_time")
                local elapsed=$((current_time - hb_time))

                if [ $elapsed -gt $threshold ]; then
                    hung_agents="$hung_agents $agent_name"
                fi
            fi
        fi
    done <<< "$agents"

    echo "$hung_agents" | xargs
}

#######################################
# Send health alert notification
# Arguments:
#   $1 - Alert type (stuck_tasks, hung_agents)
#   $2 - Details (task IDs or agent names)
#######################################
send_health_alert() {
    local alert_type=$1
    local details=$2
    local agent_name

    agent_name=$("$SCRIPT_DIR/agent-mail-helper.sh" whoami 2>/dev/null || echo "QueueMonitor")

    case "$alert_type" in
        stuck_tasks)
            local subject="[agent-health] ALERT: Stuck tasks detected"
            local body="Agent Health Monitor Alert

Detected tasks that have been in progress for >2 hours with no updates:

Stuck tasks: $details

Recommended actions:
  - Check agent status: br list --status open
  - Review task details: br show <task-id>
  - Consider reassigning stuck tasks
  - Check agent logs for errors

Auto-restart flag created for bd-3ii integration.

—Queue Monitor Daemon"
            ;;
        hung_agents)
            local subject="[agent-health] ALERT: Hung agents detected"
            local body="Agent Health Monitor Alert

Detected agents with no heartbeat for >30 minutes:

Hung agents: $details

Recommended actions:
  - Check agent sessions: tmux list-sessions
  - Review agent logs
  - Consider restarting hung agents
  - Check system resources

Auto-restart flag created for bd-3ii integration.

—Queue Monitor Daemon"
            ;;
    esac

    # Send notification
    local recipient="${COORDINATOR_RECIPIENT:-Coordinators}"
    "$SCRIPT_DIR/agent-mail-helper.sh" send "$recipient" "$subject" "$body" "agent-health" 2>/dev/null || true
    print_msg YELLOW "Health alert sent: $alert_type"

    # Create flag file for bd-3ii auto-restart integration
    mkdir -p "$PROJECT_ROOT/.beads"
    echo "$alert_type|$details" > "$PROJECT_ROOT/.beads/agent-health-alert.flag"
}

#######################################
# Perform health checks
#######################################
perform_health_checks() {
    if [ "${HEALTH_CHECK_ENABLED:-true}" != "true" ]; then
        return
    fi

    # Update heartbeats for all active agents
    local agents
    agents=$(get_active_agents)
    while IFS= read -r agent_name; do
        if [ -n "$agent_name" ]; then
            update_heartbeat "$agent_name" "periodic_check"
        fi
    done <<< "$agents"

    # Check for stuck tasks
    local stuck
    stuck=$(check_stuck_tasks)
    if [ -n "$stuck" ]; then
        print_msg RED "Stuck tasks detected: $stuck"
        send_health_alert "stuck_tasks" "$stuck"

        # Log event
        local timestamp
        timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        cat >> "$EVENTS_LOG" <<EOF
{"timestamp":"$timestamp","event":"stuck_tasks","tasks":"$stuck","monitor":"agent-health"}
EOF
    fi

    # Check for hung agents
    local hung
    hung=$(check_hung_agents)
    if [ -n "$hung" ]; then
        print_msg RED "Hung agents detected: $hung"
        send_health_alert "hung_agents" "$hung"

        # Log event
        local timestamp
        timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        cat >> "$EVENTS_LOG" <<EOF
{"timestamp":"$timestamp","event":"hung_agents","agents":"$hung","monitor":"agent-health"}
EOF
    fi
}

#######################################
# Monitor loop (runs in tmux session)
#######################################
monitor_loop() {
    local previous_level="normal"
    local check_count=0
    local health_check_counter=0

    print_msg GREEN "Queue Monitor started (interval: ${CHECK_INTERVAL}s)"
    print_msg BLUE "Thresholds: Low=$QUEUE_DEPTH_LOW, Medium=$QUEUE_DEPTH_MEDIUM, High=$QUEUE_DEPTH_HIGH, Critical=$QUEUE_DEPTH_CRITICAL"

    if [ "${HEALTH_CHECK_ENABLED:-true}" = "true" ]; then
        print_msg GREEN "Agent health monitoring enabled (stuck_task_threshold: ${STUCK_TASK_THRESHOLD:-7200}s, hung_agent_threshold: ${HUNG_AGENT_THRESHOLD:-1800}s)"
    fi

    while true; do
        check_count=$((check_count + 1))
        health_check_counter=$((health_check_counter + CHECK_INTERVAL))

        # Get current queue depth
        local depth
        depth=$(get_queue_depth)

        # Determine threshold level
        local level
        level=$(get_threshold_level "$depth")

        # Display status
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Queue depth: $depth tasks (level: $level)"

        # Check for threshold breach
        if [ "$level" != "normal" ] && [ "$level" != "$previous_level" ]; then
            print_msg YELLOW "Threshold breach detected: $level (depth: $depth)"
            log_event "$depth" "$level" "threshold_breach"
            send_notification "$depth" "$level"

            # Create flag file for bd-3ii integration
            mkdir -p "$PROJECT_ROOT/.beads"
            echo "$depth" > "$PROJECT_ROOT/.beads/queue-alert.flag"
        fi

        # Check for recovery
        if [ "$previous_level" != "normal" ] && [ "$level" = "normal" ]; then
            print_msg GREEN "Queue returned to normal (depth: $depth)"
            log_event "$depth" "$level" "recovered"

            # Remove flag file
            rm -f "$PROJECT_ROOT/.beads/queue-alert.flag"
        fi

        previous_level="$level"

        # Perform health checks periodically
        if [ $health_check_counter -ge "${HEALTH_CHECK_INTERVAL:-60}" ]; then
            perform_health_checks
            health_check_counter=0
        fi

        # Sleep until next check
        sleep "$CHECK_INTERVAL"
    done
}

#######################################
# Start daemon in tmux session
#######################################
start_daemon() {
    # Check if already running
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        print_msg YELLOW "Queue monitor is already running"
        print_msg BLUE "Attach with: tmux attach -t $SESSION_NAME"
        return 1
    fi

    # Initialize config if needed
    init_config

    # Load configuration
    load_config

    # Create tmux session
    print_msg BLUE "Starting queue monitor daemon..."

    # Start in detached session
    tmux new-session -d -s "$SESSION_NAME" "cd '$PROJECT_ROOT' && bash '$0' _monitor_loop"

    # Save PID
    mkdir -p "$(dirname "$PID_FILE")"
    tmux list-panes -t "$SESSION_NAME" -F "#{pane_pid}" > "$PID_FILE"

    print_msg GREEN "Queue monitor started in tmux session: $SESSION_NAME"
    print_msg BLUE "View status: $0 status"
    print_msg BLUE "Attach to monitor: $0 attach"
    print_msg BLUE "Stop monitor: $0 stop"
}

#######################################
# Stop daemon
#######################################
stop_daemon() {
    if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        print_msg YELLOW "Queue monitor is not running"
        return 1
    fi

    print_msg BLUE "Stopping queue monitor daemon..."
    tmux kill-session -t "$SESSION_NAME"

    # Remove PID file
    rm -f "$PID_FILE"

    print_msg GREEN "Queue monitor stopped"
}

#######################################
# Show daemon status
#######################################
show_status() {
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        print_msg GREEN "Queue monitor is RUNNING"
        print_msg BLUE "Session: $SESSION_NAME"

        # Show recent events
        if [ -f "$EVENTS_LOG" ]; then
            echo ""
            echo "Recent events (last 5):"
            tail -5 "$EVENTS_LOG" | jq -r '"\(.timestamp) | \(.event // .level) | \(.queue_depth // .tasks // .agents // "N/A")"' 2>/dev/null || tail -5 "$EVENTS_LOG"
        fi

        # Show agent health status
        if [ -f "$HEARTBEAT_LOG" ]; then
            echo ""
            echo "Agent heartbeats (last 5):"
            tail -5 "$HEARTBEAT_LOG" | jq -r '"\(.timestamp) | \(.agent) | \(.activity)"' 2>/dev/null || tail -5 "$HEARTBEAT_LOG"
        fi

        # Check for active alerts
        if [ -f "$PROJECT_ROOT/.beads/agent-health-alert.flag" ]; then
            echo ""
            print_msg RED "⚠️  ACTIVE HEALTH ALERT:"
            cat "$PROJECT_ROOT/.beads/agent-health-alert.flag"
        fi

        echo ""
        print_msg BLUE "Attach with: tmux attach -t $SESSION_NAME"
    else
        print_msg YELLOW "Queue monitor is NOT running"
        print_msg BLUE "Start with: $0 start"
    fi
}

#######################################
# Attach to daemon session
#######################################
attach_daemon() {
    if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        print_msg RED "Queue monitor is not running"
        print_msg BLUE "Start with: $0 start"
        return 1
    fi

    print_msg GREEN "Attaching to queue monitor..."
    print_msg BLUE "(Press Ctrl+B then D to detach)"
    sleep 1
    tmux attach -t "$SESSION_NAME"
}

#######################################
# Print usage
#######################################
usage() {
    cat <<EOF
Usage: $(basename "$0") {start|stop|status|attach}

Queue Monitor Daemon - Watches task queue depth and agent health

Commands:
  start   - Start daemon in tmux session
  stop    - Stop daemon
  status  - Show daemon status and recent events
  attach  - Attach to daemon session (Ctrl+B D to detach)

Features:
  - Queue depth monitoring with multi-tier thresholds
  - Agent health monitoring (bd-13b)
    * Stuck task detection (>2hr no updates)
    * Hung agent detection (>30min no heartbeat)
    * Auto-restart integration with bd-3ii

Configuration:
  Edit thresholds in: $THRESHOLDS_FILE

Event logs:
  $EVENTS_LOG
  $HEARTBEAT_LOG

Part of: bd-10w, bd-13b (Phase 1 NTM Implementation)
EOF
}

#######################################
# Main
#######################################
case "${1:-}" in
    start)
        start_daemon
        ;;
    stop)
        stop_daemon
        ;;
    status)
        show_status
        ;;
    attach)
        attach_daemon
        ;;
    _monitor_loop)
        # Internal: called by tmux session
        load_config
        monitor_loop
        ;;
    *)
        usage
        exit 1
        ;;
esac
