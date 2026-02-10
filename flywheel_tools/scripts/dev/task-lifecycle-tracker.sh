#!/usr/bin/env bash
# task-lifecycle-tracker.sh - Track full task lifecycle for feedback loop optimization
#
# Usage:
#   ./scripts/task-lifecycle-tracker.sh claim <agent> <task-id>
#   ./scripts/task-lifecycle-tracker.sh start <agent> <task-id>
#   ./scripts/task-lifecycle-tracker.sh complete <agent> <task-id> [success|failed]
#   ./scripts/task-lifecycle-tracker.sh stats [agent|task-id]
#   ./scripts/task-lifecycle-tracker.sh cycle-time [agent|type]
#   ./scripts/task-lifecycle-tracker.sh success-rate [agent|type]
#   ./scripts/task-lifecycle-tracker.sh feed-autoscaler
#
# Tracks:
#   - Task claim time (when agent claims task)
#   - Task start time (when agent actually begins work)
#   - Task completion time (when work finishes)
#   - Success/failure status
#   - Cycle time (claim → completion)
#   - Failure patterns by task type
#
# Part of: bd-2pfa - Task Completion Feedback Loop

set -euo pipefail

# Project root and paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LIFECYCLE_FILE="$PROJECT_ROOT/.beads/task-lifecycle.jsonl"
QUEUE_EVENTS_FILE="$PROJECT_ROOT/.beads/queue-events.jsonl"
TASK_ANALYZER="$PROJECT_ROOT/scripts/task-analyzer.sh"

# Ensure files exist
mkdir -p "$PROJECT_ROOT/.beads"
touch "$LIFECYCLE_FILE"
touch "$QUEUE_EVENTS_FILE"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#######################################
# Print colored message
#######################################
print_msg() {
    local color="${!1}"
    local msg="$2"
    echo -e "${color}${msg}${NC}" >&2
}

#######################################
# Get current timestamp (ISO 8601)
#######################################
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

#######################################
# Get epoch timestamp
#######################################
get_epoch() {
    date +%s
}

#######################################
# Record lifecycle event
# Arguments:
#   $1 - Agent name
#   $2 - Task ID
#   $3 - Event type (claimed, started, completed, failed)
#   $4 - Optional status/notes
#######################################
record_event() {
    local agent="$1"
    local task_id="$2"
    local event="$3"
    local status="${4:-}"

    local timestamp=$(get_timestamp)
    local epoch=$(get_epoch)

    # Record to lifecycle file
    local lifecycle_entry=$(jq -nc \
        --arg agent "$agent" \
        --arg task "$task_id" \
        --arg event "$event" \
        --arg ts "$timestamp" \
        --argjson epoch "$epoch" \
        --arg status "$status" \
        '{agent: $agent, task_id: $task, event: $event, timestamp: $ts, epoch: $epoch, status: $status}')

    echo "$lifecycle_entry" >> "$LIFECYCLE_FILE"

    # Also record to queue events for monitoring integration
    local queue_entry=$(jq -nc \
        --arg event "task_$event" \
        --arg ts "$timestamp" \
        --arg agent "$agent" \
        --arg task "$task_id" \
        --arg status "$status" \
        '{timestamp: $ts, event: $event, agent: $agent, task_id: $task, status: $status, source: "lifecycle-tracker"}')

    echo "$queue_entry" >> "$QUEUE_EVENTS_FILE"
}

#######################################
# Command: claim
# Record when agent claims a task
#######################################
cmd_claim() {
    if [ $# -lt 2 ]; then
        print_msg RED "Error: 'claim' requires agent name and task ID"
        exit 1
    fi

    local agent="$1"
    local task_id="$2"

    record_event "$agent" "$task_id" "claimed" ""
    print_msg GREEN "✓ Recorded claim: $agent → $task_id"
}

#######################################
# Command: start
# Record when agent starts working on task
#######################################
cmd_start() {
    if [ $# -lt 2 ]; then
        print_msg RED "Error: 'start' requires agent name and task ID"
        exit 1
    fi

    local agent="$1"
    local task_id="$2"

    record_event "$agent" "$task_id" "started" ""
    print_msg GREEN "✓ Recorded start: $agent → $task_id"
}

#######################################
# Command: complete
# Record when agent completes task
#######################################
cmd_complete() {
    if [ $# -lt 2 ]; then
        print_msg RED "Error: 'complete' requires agent name and task ID"
        exit 1
    fi

    local agent="$1"
    local task_id="$2"
    local status="${3:-success}"

    # Validate status
    if [ "$status" != "success" ] && [ "$status" != "failed" ]; then
        print_msg YELLOW "Warning: Invalid status '$status', using 'success'"
        status="success"
    fi

    # Record completion event
    if [ "$status" = "failed" ]; then
        record_event "$agent" "$task_id" "failed" "$status"
    else
        record_event "$agent" "$task_id" "completed" "$status"
    fi

    # Calculate cycle time
    local claim_time=$(grep "\"task_id\":\"$task_id\"" "$LIFECYCLE_FILE" | grep "\"event\":\"claimed\"" | tail -1 | jq -r '.epoch' 2>/dev/null || echo "0")
    local complete_time=$(get_epoch)

    if [ "$claim_time" != "0" ] && [ "$claim_time" != "null" ]; then
        local cycle_seconds=$((complete_time - claim_time))
        local cycle_hours=$(echo "scale=2; $cycle_seconds / 3600" | bc 2>/dev/null || echo "0")

        print_msg GREEN "✓ Recorded completion: $agent → $task_id (status: $status, cycle: ${cycle_hours}h)"
    else
        print_msg GREEN "✓ Recorded completion: $agent → $task_id (status: $status)"
    fi
}

#######################################
# Command: stats
# Show lifecycle statistics
#######################################
cmd_stats() {
    local filter="${1:-}"

    if [ ! -s "$LIFECYCLE_FILE" ]; then
        print_msg YELLOW "No lifecycle data available"
        return 0
    fi

    local data=""
    if [ -n "$filter" ]; then
        # Filter by agent or task
        data=$(grep -E "\"agent\":\"$filter\"|\"task_id\":\"$filter\"" "$LIFECYCLE_FILE" 2>/dev/null || echo "")
    else
        data=$(cat "$LIFECYCLE_FILE")
    fi

    if [ -z "$data" ]; then
        print_msg YELLOW "No data found for filter: $filter"
        return 0
    fi

    # Count events (ensure clean numeric values)
    local claimed=$(echo "$data" | grep -c "\"event\":\"claimed\"" 2>/dev/null || echo "0")
    claimed=$(echo "$claimed" | tr -d ' \n\r' | grep -E '^[0-9]+$' || echo "0")

    local started=$(echo "$data" | grep -c "\"event\":\"started\"" 2>/dev/null || echo "0")
    started=$(echo "$started" | tr -d ' \n\r' | grep -E '^[0-9]+$' || echo "0")

    local completed=$(echo "$data" | grep -c "\"event\":\"completed\"" 2>/dev/null || echo "0")
    completed=$(echo "$completed" | tr -d ' \n\r' | grep -E '^[0-9]+$' || echo "0")

    local failed=$(echo "$data" | grep -c "\"event\":\"failed\"" 2>/dev/null || echo "0")
    failed=$(echo "$failed" | tr -d ' \n\r' | grep -E '^[0-9]+$' || echo "0")

    local total_finished=$((completed + failed))
    local success_rate=0
    if [ $total_finished -gt 0 ]; then
        success_rate=$(echo "scale=1; ($completed * 100) / $total_finished" | bc 2>/dev/null || echo "0")
    fi

    # Display stats
    print_msg BLUE "Lifecycle Statistics"
    if [ -n "$filter" ]; then
        echo "Filter: $filter"
    fi
    echo "===================="
    echo "Tasks claimed: $claimed"
    echo "Tasks started: $started"
    echo "Tasks completed: $completed"
    echo "Tasks failed: $failed"
    if [ $total_finished -gt 0 ]; then
        echo "Success rate: ${success_rate}%"
    fi
}

#######################################
# Command: cycle-time
# Calculate average cycle time
#######################################
cmd_cycle_time() {
    local filter="${1:-}"

    if [ ! -s "$LIFECYCLE_FILE" ]; then
        print_msg YELLOW "No lifecycle data available"
        return 0
    fi

    # Get all completed tasks
    local completed_tasks=$(grep "\"event\":\"completed\"\|\"event\":\"failed\"" "$LIFECYCLE_FILE" | jq -r '.task_id' | sort -u)

    if [ -z "$completed_tasks" ]; then
        print_msg YELLOW "No completed tasks found"
        return 0
    fi

    local total_cycle=0
    local count=0

    while IFS= read -r task_id; do
        if [ -n "$task_id" ]; then
            # Apply filter if specified
            if [ -n "$filter" ]; then
                local task_agent=$(grep "\"task_id\":\"$task_id\"" "$LIFECYCLE_FILE" | head -1 | jq -r '.agent' 2>/dev/null || echo "")
                if [ "$task_agent" != "$filter" ]; then
                    continue
                fi
            fi

            # Get claim and completion times
            local claim_time=$(grep "\"task_id\":\"$task_id\"" "$LIFECYCLE_FILE" | grep "\"event\":\"claimed\"" | tail -1 | jq -r '.epoch' 2>/dev/null || echo "0")
            local complete_time=$(grep "\"task_id\":\"$task_id\"" "$LIFECYCLE_FILE" | grep -E "\"event\":\"completed\"|\"event\":\"failed\"" | tail -1 | jq -r '.epoch' 2>/dev/null || echo "0")

            if [ "$claim_time" != "0" ] && [ "$complete_time" != "0" ] && [ "$claim_time" != "null" ] && [ "$complete_time" != "null" ]; then
                local cycle=$((complete_time - claim_time))
                total_cycle=$((total_cycle + cycle))
                ((count++))
            fi
        fi
    done <<< "$completed_tasks"

    if [ $count -eq 0 ]; then
        print_msg YELLOW "No cycle time data available"
        return 0
    fi

    local avg_cycle=$((total_cycle / count))
    local avg_hours=$(echo "scale=2; $avg_cycle / 3600" | bc 2>/dev/null || echo "0")

    print_msg BLUE "Cycle Time Statistics"
    if [ -n "$filter" ]; then
        echo "Filter: $filter"
    fi
    echo "======================"
    echo "Tasks analyzed: $count"
    echo "Average cycle time: ${avg_hours}h (${avg_cycle}s)"
}

#######################################
# Command: success-rate
# Calculate success rate by agent or type
#######################################
cmd_success_rate() {
    local filter="${1:-}"

    if [ ! -s "$LIFECYCLE_FILE" ]; then
        print_msg YELLOW "No lifecycle data available"
        return 0
    fi

    local data=""
    if [ -n "$filter" ]; then
        data=$(grep "\"agent\":\"$filter\"" "$LIFECYCLE_FILE" 2>/dev/null || echo "")
    else
        data=$(cat "$LIFECYCLE_FILE")
    fi

    if [ -z "$data" ]; then
        print_msg YELLOW "No data found for filter: $filter"
        return 0
    fi

    local completed=$(echo "$data" | grep -c "\"event\":\"completed\"" 2>/dev/null || echo "0")
    completed=$(echo "$completed" | tr -d ' \n\r' | grep -E '^[0-9]+$' || echo "0")

    local failed=$(echo "$data" | grep -c "\"event\":\"failed\"" 2>/dev/null || echo "0")
    failed=$(echo "$failed" | tr -d ' \n\r' | grep -E '^[0-9]+$' || echo "0")

    local total=$((completed + failed))

    if [ $total -eq 0 ]; then
        print_msg YELLOW "No completed tasks found"
        return 0
    fi

    local rate=$(echo "scale=1; ($completed * 100) / $total" | bc 2>/dev/null || echo "0")

    print_msg BLUE "Success Rate"
    if [ -n "$filter" ]; then
        echo "Filter: $filter"
    fi
    echo "=============="
    echo "Completed: $completed"
    echo "Failed: $failed"
    echo "Success rate: ${rate}%"
}

#######################################
# Command: feed-autoscaler
# Generate metrics for auto-scaler consumption
#######################################
cmd_feed_autoscaler() {
    if [ ! -s "$LIFECYCLE_FILE" ]; then
        echo '{"completion_rate": 0, "avg_cycle_time": 0, "success_rate": 0, "active_tasks": 0}'
        return 0
    fi

    # Calculate metrics for last hour
    local now=$(get_epoch)
    local hour_ago=$((now - 3600))

    # Recent completions (last hour)
    local recent_completed=$(jq -r --argjson cutoff "$hour_ago" 'select(.epoch >= $cutoff and (.event == "completed" or .event == "failed"))' "$LIFECYCLE_FILE" 2>/dev/null | wc -l | tr -d ' \n\r')
    recent_completed=$(echo "${recent_completed:-0}" | grep -E '^[0-9]+$' || echo "0")

    # Calculate completion rate (tasks per hour)
    local completion_rate=$recent_completed

    # Active tasks (claimed but not completed)
    local claimed_tasks=$(grep "\"event\":\"claimed\"" "$LIFECYCLE_FILE" | jq -r '.task_id' | sort -u)
    local completed_tasks=$(grep -E "\"event\":\"completed\"|\"event\":\"failed\"" "$LIFECYCLE_FILE" | jq -r '.task_id' | sort -u)

    local active=0
    if [ -n "$claimed_tasks" ]; then
        while IFS= read -r task; do
            if [ -n "$task" ] && ! echo "$completed_tasks" | grep -q "^$task$"; then
                ((active++))
            fi
        done <<< "$claimed_tasks"
    fi

    # Overall success rate
    local all_completed=$(grep -c "\"event\":\"completed\"" "$LIFECYCLE_FILE" 2>/dev/null || echo "0")
    all_completed=$(echo "$all_completed" | tr -d ' \n\r' | grep -E '^[0-9]+$' || echo "0")

    local all_failed=$(grep -c "\"event\":\"failed\"" "$LIFECYCLE_FILE" 2>/dev/null || echo "0")
    all_failed=$(echo "$all_failed" | tr -d ' \n\r' | grep -E '^[0-9]+$' || echo "0")

    local all_total=$((all_completed + all_failed))

    local success_rate=100
    if [ $all_total -gt 0 ]; then
        success_rate=$(echo "scale=1; ($all_completed * 100) / $all_total" | bc 2>/dev/null || echo "100")
    fi

    # Average cycle time
    local avg_cycle=0
    local cycle_data=$(cmd_cycle_time 2>/dev/null | grep "Average cycle time:" | sed -n 's/.*(\([0-9]*\)s).*/\1/p' || echo "0")
    if [ -n "$cycle_data" ] && [ "$cycle_data" != "0" ]; then
        avg_cycle=$cycle_data
    fi

    # Output JSON for auto-scaler
    jq -nc \
        --argjson rate "$completion_rate" \
        --argjson cycle "$avg_cycle" \
        --argjson success "$success_rate" \
        --argjson active "$active" \
        '{completion_rate: $rate, avg_cycle_time: $cycle, success_rate: $success, active_tasks: $active}'
}

#######################################
# Print usage
#######################################
usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [arguments]

Commands:
  claim <agent> <task-id>              Record task claim
  start <agent> <task-id>              Record task start
  complete <agent> <task-id> [status]  Record task completion (status: success|failed)
  stats [filter]                       Show lifecycle statistics (filter: agent or task-id)
  cycle-time [filter]                  Calculate average cycle time
  success-rate [filter]                Calculate success rate
  feed-autoscaler                      Generate metrics for auto-scaler (JSON)

Examples:
  $(basename "$0") claim DarkGlen bd-2pfa
  $(basename "$0") start DarkGlen bd-2pfa
  $(basename "$0") complete DarkGlen bd-2pfa success
  $(basename "$0") stats DarkGlen
  $(basename "$0") cycle-time
  $(basename "$0") feed-autoscaler

Lifecycle Events:
  claimed  → Agent claims task from queue
  started  → Agent begins actual work
  completed → Task finished successfully
  failed   → Task could not be completed

Metrics:
  - Cycle time: Time from claim to completion
  - Success rate: Percentage of tasks completed successfully
  - Completion rate: Tasks completed per hour
  - Active tasks: Tasks claimed but not yet completed

Integration:
  - Records events to .beads/task-lifecycle.jsonl
  - Publishes events to .beads/queue-events.jsonl for monitoring
  - Provides metrics to auto-scaler for intelligent spawning

Part of: bd-2pfa - Task Completion Feedback Loop

EOF
}

#######################################
# Main function
#######################################
main() {
    if [ $# -eq 0 ]; then
        usage
        exit 1
    fi

    local command="$1"
    shift

    case "$command" in
        claim)
            cmd_claim "$@"
            ;;
        start)
            cmd_start "$@"
            ;;
        complete)
            cmd_complete "$@"
            ;;
        stats)
            cmd_stats "$@"
            ;;
        cycle-time)
            cmd_cycle_time "$@"
            ;;
        success-rate)
            cmd_success_rate "$@"
            ;;
        feed-autoscaler)
            cmd_feed_autoscaler
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            print_msg RED "Error: Unknown command '$command'"
            usage
            exit 1
            ;;
    esac
}

main "$@"
