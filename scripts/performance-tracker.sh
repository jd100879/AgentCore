#!/usr/bin/env bash
# performance-tracker.sh - Track agent-task completion data for performance profiling
#
# Usage:
#   ./scripts/performance-tracker.sh start <agent-name> <task-id>
#   ./scripts/performance-tracker.sh complete <agent-name> <task-id> [quality]
#   ./scripts/performance-tracker.sh stats <agent-name>
#   ./scripts/performance-tracker.sh task-stats <task-labels>
#
# Data tracked:
#   - Start time, completion time, duration
#   - Task labels/capabilities
#   - Quality score (optional: 0-100)
#
# Part of: bd-3si - Performance Tracker (Phase 1 NTM)

set -euo pipefail

# Project root and paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PERFORMANCE_FILE="$PROJECT_ROOT/.beads/agent-performance.jsonl"
ACTIVE_TASKS_FILE="$PROJECT_ROOT/.beads/active-task-tracking.jsonl"

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
# Print usage
#######################################
usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [arguments]

Commands:
  start <agent> <task-id>              Record task start time
  complete <agent> <task-id> [quality] Record task completion (quality: 0-100)
  score <agent> <labels>               Calculate history score for agent+labels (0.0-1.0)
  stats <agent>                        Show performance stats for agent
  task-stats <labels>                  Show performance stats for task type
  history <agent> [limit]              Show completion history for agent

Performance Metrics:
  - Average completion time by task type
  - Task completion rate
  - Quality scores (if provided)
  - Success patterns (task types agent excels at)

Examples:
  $(basename "$0") start HazyFinch bd-1rm
  $(basename "$0") complete HazyFinch bd-1rm 95
  $(basename "$0") score HazyFinch "phase1,ntm,monitoring"
  $(basename "$0") stats HazyFinch
  $(basename "$0") task-stats "backend,api"
  $(basename "$0") history HazyFinch 10

Output:
  Performance data is stored in .beads/agent-performance.jsonl
  Active tasks are tracked in .beads/active-task-tracking.jsonl

EOF
}

#######################################
# Ensure performance files exist
#######################################
ensure_files() {
    mkdir -p "$PROJECT_ROOT/.beads"
    touch "$PERFORMANCE_FILE"
    touch "$ACTIVE_TASKS_FILE"
}

#######################################
# Get task labels from Beads
# Arguments:
#   $1 - Task ID
# Returns: Comma-separated labels
#######################################
get_task_labels() {
    local task_id="$1"

    local task_details=$(br show "$task_id" 2>/dev/null || echo "")

    if [ -z "$task_details" ]; then
        echo ""
        return
    fi

    # Extract labels
    local labels=$(echo "$task_details" | grep "^Labels:" | sed 's/^Labels: //' | tr ', ' ',' || echo "")
    echo "$labels"
}

#######################################
# Start tracking a task
# Arguments:
#   $1 - Agent name
#   $2 - Task ID
#######################################
cmd_start() {
    if [ $# -lt 2 ]; then
        print_msg RED "Error: 'start' requires agent name and task ID"
        usage
        exit 1
    fi

    local agent_name="$1"
    local task_id="$2"

    ensure_files

    # Get task labels
    local labels=$(get_task_labels "$task_id")

    # Record start time
    local start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Create tracking entry (compact JSON)
    local entry=$(jq -ncc \
        --arg agent "$agent_name" \
        --arg task "$task_id" \
        --arg labels "$labels" \
        --arg start "$start_time" \
        '{agent: $agent, task_id: $task, labels: $labels, start_time: $start}')

    # Append to active tasks file
    echo "$entry" >> "$ACTIVE_TASKS_FILE"

    print_msg GREEN "Started tracking $task_id for $agent_name"
}

#######################################
# Complete a task and record performance
# Arguments:
#   $1 - Agent name
#   $2 - Task ID
#   $3 - Quality score (optional, 0-100)
#######################################
cmd_complete() {
    if [ $# -lt 2 ]; then
        print_msg RED "Error: 'complete' requires agent name and task ID"
        usage
        exit 1
    fi

    local agent_name="$1"
    local task_id="$2"
    local quality="${3:-}"

    ensure_files

    # Find active tracking entry
    local active_entry=$(grep "\"agent\":\"$agent_name\"" "$ACTIVE_TASKS_FILE" 2>/dev/null | grep "\"task_id\":\"$task_id\"" | tail -1 || echo "")

    if [ -z "$active_entry" ]; then
        print_msg YELLOW "Warning: No active tracking found for $task_id by $agent_name"
        print_msg YELLOW "Recording completion without start time"

        # Create entry with just completion time
        local completion_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        local labels=$(get_task_labels "$task_id")

        local entry=$(jq -nc \
            --arg agent "$agent_name" \
            --arg task "$task_id" \
            --arg labels "$labels" \
            --arg complete "$completion_time" \
            --arg quality "$quality" \
            '{agent: $agent, task_id: $task, labels: $labels, completion_time: $complete, quality: ($quality | if . == "" then null else tonumber end)}')

        echo "$entry" >> "$PERFORMANCE_FILE"
        print_msg GREEN "Recorded completion for $task_id"
        return
    fi

    # Extract start time and labels from active entry
    local start_time=$(echo "$active_entry" | jq -r '.start_time')
    local labels=$(echo "$active_entry" | jq -r '.labels')

    # Calculate duration
    local completion_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local start_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$start_time" "+%s" 2>/dev/null || echo "0")
    local complete_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$completion_time" "+%s" 2>/dev/null || echo "0")
    local duration=$((complete_epoch - start_epoch))

    # Create performance record
    local entry=$(jq -nc \
        --arg agent "$agent_name" \
        --arg task "$task_id" \
        --arg labels "$labels" \
        --arg start "$start_time" \
        --arg complete "$completion_time" \
        --argjson duration "$duration" \
        --arg quality "$quality" \
        '{agent: $agent, task_id: $task, labels: $labels, start_time: $start, completion_time: $complete, duration_seconds: $duration, quality: ($quality | if . == "" then null else tonumber end)}')

    # Append to performance file
    echo "$entry" >> "$PERFORMANCE_FILE"

    # Remove from active tasks
    grep -v "\"agent\":\"$agent_name\".*\"task_id\":\"$task_id\"" "$ACTIVE_TASKS_FILE" > "$ACTIVE_TASKS_FILE.tmp" 2>/dev/null || true
    mv "$ACTIVE_TASKS_FILE.tmp" "$ACTIVE_TASKS_FILE" 2>/dev/null || true

    # Display summary
    local duration_hours=$(echo "scale=2; $duration / 3600" | bc 2>/dev/null || echo "0")
    print_msg GREEN "Completed $task_id for $agent_name"
    echo "  Duration: ${duration}s (${duration_hours}h)"
    if [ -n "$quality" ]; then
        echo "  Quality: $quality/100"
    fi
}

#######################################
# Calculate history score for agent with specific labels
# Arguments:
#   $1 - Agent name
#   $2 - Task labels (comma-separated)
# Returns: Success rate 0.0-1.0 (default 0.5 if no history)
#######################################
cmd_score() {
    if [ $# -lt 1 ]; then
        print_msg RED "Error: 'score' requires agent name" >&2
        exit 1
    fi

    local agent_name="$1"
    local target_labels="${2:-}"

    ensure_files

    # Get all completed tasks for this agent
    local completed=$(grep "\"agent\":\"$agent_name\"" "$PERFORMANCE_FILE" 2>/dev/null || echo "")

    if [ -z "$completed" ]; then
        # No history, return neutral score
        echo "0.5"
        return
    fi

    # If labels provided, filter for tasks with matching labels
    local relevant_tasks="$completed"
    if [ -n "$target_labels" ]; then
        IFS=',' read -ra label_array <<< "$target_labels"

        local filtered=""
        while IFS= read -r line; do
            local task_labels=$(echo "$line" | jq -r '.labels // ""')

            # Check if any target label matches task labels
            local match=false
            for label in "${label_array[@]}"; do
                label=$(echo "$label" | tr -d ' ')
                if [[ "$task_labels" == *"$label"* ]]; then
                    match=true
                    break
                fi
            done

            if [ "$match" = true ]; then
                filtered+="$line"$'\n'
            fi
        done <<< "$completed"

        # Use filtered tasks if any match, otherwise fall back to all completed
        if [ -n "$filtered" ]; then
            relevant_tasks="$filtered"
        else
            # No exact matches, use all agent history with reduced weight
            relevant_tasks="$completed"
        fi
    fi

    # Calculate average quality score
    local total_quality=0
    local quality_count=0

    while IFS= read -r line; do
        if [ -z "$line" ]; then continue; fi

        local quality=$(echo "$line" | jq -r '.quality // null')
        if [ "$quality" != "null" ] && [ -n "$quality" ]; then
            total_quality=$(echo "$total_quality + $quality" | bc 2>/dev/null || echo "$total_quality")
            ((quality_count++))
        fi
    done <<< "$relevant_tasks"

    if [ $quality_count -eq 0 ]; then
        # No quality scores available, return neutral
        echo "0.5"
        return
    fi

    # Calculate average quality
    local avg_quality=$(echo "scale=1; $total_quality / $quality_count" | bc 2>/dev/null || echo "50")

    # Convert quality (0-100) to score (0.0-1.0)
    # Quality 0 = 0.1 (minimum), Quality 100 = 1.0
    # Formula: 0.1 + (quality/100) * 0.9
    local score=$(echo "scale=2; 0.1 + ($avg_quality / 100.0) * 0.9" | bc -l)

    # Ensure score is within bounds
    if (( $(echo "$score < 0.1" | bc -l) )); then
        echo "0.1"
    elif (( $(echo "$score > 1.0" | bc -l) )); then
        echo "1.0"
    else
        echo "$score"
    fi
}

#######################################
# Show performance stats for agent
# Arguments:
#   $1 - Agent name
#######################################
cmd_stats() {
    if [ $# -lt 1 ]; then
        print_msg RED "Error: 'stats' requires agent name"
        usage
        exit 1
    fi

    local agent_name="$1"

    ensure_files

    # Get all completed tasks for this agent
    local completed=$(grep "\"agent\":\"$agent_name\"" "$PERFORMANCE_FILE" 2>/dev/null || echo "")

    if [ -z "$completed" ]; then
        print_msg YELLOW "No performance data found for $agent_name"
        return
    fi

    # Count total completions
    local total_count=$(echo "$completed" | wc -l | xargs)

    # Calculate average duration
    local total_duration=0
    local duration_count=0

    while IFS= read -r line; do
        local duration=$(echo "$line" | jq -r '.duration_seconds // 0')
        if [ "$duration" != "0" ] && [ "$duration" != "null" ]; then
            total_duration=$((total_duration + duration))
            ((duration_count++))
        fi
    done <<< "$completed"

    local avg_duration=0
    if [ $duration_count -gt 0 ]; then
        avg_duration=$((total_duration / duration_count))
    fi

    local avg_hours=$(echo "scale=2; $avg_duration / 3600" | bc 2>/dev/null || echo "0")

    # Calculate average quality
    local total_quality=0
    local quality_count=0

    while IFS= read -r line; do
        local quality=$(echo "$line" | jq -r '.quality // null')
        if [ "$quality" != "null" ] && [ -n "$quality" ]; then
            total_quality=$(echo "$total_quality + $quality" | bc 2>/dev/null || echo "$total_quality")
            ((quality_count++))
        fi
    done <<< "$completed"

    local avg_quality=0
    if [ $quality_count -gt 0 ]; then
        avg_quality=$(echo "scale=1; $total_quality / $quality_count" | bc 2>/dev/null || echo "0")
    fi

    # Display stats
    print_msg BLUE "Performance Stats for $agent_name"
    echo "======================================"
    echo "Total completions: $total_count"
    if [ $duration_count -gt 0 ]; then
        echo "Average duration: ${avg_hours}h (${avg_duration}s)"
    fi
    if [ $quality_count -gt 0 ]; then
        echo "Average quality: ${avg_quality}/100"
    fi
    echo ""

    # Show task type breakdown
    echo "Completions by task type:"
    echo "$completed" | jq -r '.labels // "unknown"' | tr ',' '\n' | sort | uniq -c | sort -rn | head -5
}

#######################################
# Show completion history for agent
# Arguments:
#   $1 - Agent name
#   $2 - Limit (optional, default 10)
#######################################
cmd_history() {
    if [ $# -lt 1 ]; then
        print_msg RED "Error: 'history' requires agent name"
        usage
        exit 1
    fi

    local agent_name="$1"
    local limit="${2:-10}"

    ensure_files

    print_msg BLUE "Completion History for $agent_name (last $limit)"
    echo "======================================"

    grep "\"agent\":\"$agent_name\"" "$PERFORMANCE_FILE" 2>/dev/null | tail -"$limit" | while IFS= read -r line; do
        local task_id=$(echo "$line" | jq -r '.task_id')
        local duration=$(echo "$line" | jq -r '.duration_seconds // "N/A"')
        local quality=$(echo "$line" | jq -r '.quality // "N/A"')
        local labels=$(echo "$line" | jq -r '.labels // "unknown"')

        if [ "$duration" != "N/A" ]; then
            local hours=$(echo "scale=2; $duration / 3600" | bc 2>/dev/null || echo "0")
            duration="${hours}h"
        fi

        printf "%-12s | %-6s | Q:%-3s | %s\n" "$task_id" "$duration" "$quality" "$labels"
    done
}

#######################################
# Show performance stats for task type
# Arguments:
#   $1 - Task labels (comma-separated)
#######################################
cmd_task_stats() {
    if [ $# -lt 1 ]; then
        print_msg RED "Error: 'task-stats' requires task labels"
        usage
        exit 1
    fi

    local target_labels="$1"

    ensure_files

    # Find tasks with matching labels
    local matching=$(grep -i "$target_labels" "$PERFORMANCE_FILE" 2>/dev/null || echo "")

    if [ -z "$matching" ]; then
        print_msg YELLOW "No performance data found for tasks with labels: $target_labels"
        return
    fi

    # Count total
    local total_count=$(echo "$matching" | wc -l | xargs)

    # Calculate average duration
    local total_duration=0
    local duration_count=0

    while IFS= read -r line; do
        local duration=$(echo "$line" | jq -r '.duration_seconds // 0')
        if [ "$duration" != "0" ] && [ "$duration" != "null" ]; then
            total_duration=$((total_duration + duration))
            ((duration_count++))
        fi
    done <<< "$matching"

    local avg_duration=0
    if [ $duration_count -gt 0 ]; then
        avg_duration=$((total_duration / duration_count))
    fi

    local avg_hours=$(echo "scale=2; $avg_duration / 3600" | bc 2>/dev/null || echo "0")

    # Show top performers for this task type
    print_msg BLUE "Performance Stats for tasks: $target_labels"
    echo "======================================"
    echo "Total completions: $total_count"
    if [ $duration_count -gt 0 ]; then
        echo "Average duration: ${avg_hours}h (${avg_duration}s)"
    fi
    echo ""
    echo "Top performers:"
    echo "$matching" | jq -r '.agent' | sort | uniq -c | sort -rn | head -5
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
        start)
            cmd_start "$@"
            ;;
        complete)
            cmd_complete "$@"
            ;;
        score)
            cmd_score "$@"
            ;;
        stats)
            cmd_stats "$@"
            ;;
        history)
            cmd_history "$@"
            ;;
        task-stats)
            cmd_task_stats "$@"
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
