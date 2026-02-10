#!/usr/bin/env bash
# swarm-metrics.sh - Track swarm orchestration usage and efficiency
#
# Logs swarm spawns, coordination time, task distribution for Phase 4 evaluation
# Usage: ./scripts/swarm-metrics.sh [--summary]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
METRICS_DIR="$PROJECT_ROOT/docs/metrics"
METRICS_FILE="$METRICS_DIR/swarm-metrics.jsonl"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_msg() {
    local color=$1
    shift
    echo -e "${!color}$*${NC}"
}

# Initialize metrics file
init_metrics() {
    mkdir -p "$METRICS_DIR"
    if [[ ! -f "$METRICS_FILE" ]]; then
        echo "# Swarm metrics log (JSONL format)" > "$METRICS_FILE"
        print_msg GREEN "✓ Initialized $METRICS_FILE"
    fi
}

# Log swarm spawn
log_spawn() {
    local agent_count="$1"
    local swarm_name="${2:-swarm}"
    local spawn_duration_ms="${3:-0}"

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local record=$(cat <<EOF
{"timestamp":"$timestamp","event":"spawn","agent_count":$agent_count,"swarm_name":"$swarm_name","duration_ms":$spawn_duration_ms}
EOF
)

    echo "$record" >> "$METRICS_FILE"
    print_msg BLUE "Logged swarm spawn: $agent_count agents, ${spawn_duration_ms}ms"
}

# Log task assignment
log_assignment() {
    local task_count="$1"
    local assignment_time_ms="${2:-0}"
    local method="${3:-manual}" # manual, round-robin, capability

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local record=$(cat <<EOF
{"timestamp":"$timestamp","event":"assign","task_count":$task_count,"duration_ms":$assignment_time_ms,"method":"$method"}
EOF
)

    echo "$record" >> "$METRICS_FILE"
    print_msg BLUE "Logged task assignment: $task_count tasks, ${assignment_time_ms}ms, method=$method"
}

# Log coordination overhead
log_coordination() {
    local activity="$1" # spawn, assign, monitor, teardown
    local time_spent_seconds="$2"

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local time_ms=$((time_spent_seconds * 1000))

    local record=$(cat <<EOF
{"timestamp":"$timestamp","event":"coordination","activity":"$activity","time_ms":$time_ms}
EOF
)

    echo "$record" >> "$METRICS_FILE"
    print_msg BLUE "Logged coordination: $activity, ${time_spent_seconds}s"
}

# Analyze swarm metrics
analyze_metrics() {
    if [[ ! -f "$METRICS_FILE" ]]; then
        print_msg YELLOW "No metrics data yet"
        return
    fi

    print_msg GREEN "=== Swarm Metrics Analysis ==="
    echo ""

    # Total swarm spawns
    local total_spawns=$(grep '"event":"spawn"' "$METRICS_FILE" 2>/dev/null | wc -l | tr -d ' ')
    print_msg BLUE "Total swarm spawns: $total_spawns"

    if [[ $total_spawns -eq 0 ]]; then
        print_msg YELLOW "No swarm data collected yet"
        return
    fi

    # Average swarm size
    local avg_size=$(grep '"event":"spawn"' "$METRICS_FILE" | \
        grep -o '"agent_count":[0-9]*' | \
        cut -d: -f2 | \
        awk '{sum+=$1; count++} END {if (count>0) print int(sum/count); else print 0}')
    print_msg BLUE "Average swarm size: $avg_size agents"

    # Average spawn duration
    local avg_spawn=$(grep '"event":"spawn"' "$METRICS_FILE" | \
        grep -o '"duration_ms":[0-9]*' | \
        cut -d: -f2 | \
        awk '{sum+=$1; count++} END {if (count>0) print int(sum/count); else print 0}')
    print_msg BLUE "Average spawn time: ${avg_spawn} ms"

    # Total coordination time
    local total_coord=$(grep '"event":"coordination"' "$METRICS_FILE" | \
        grep -o '"time_ms":[0-9]*' | \
        cut -d: -f2 | \
        awk '{sum+=$1} END {print int(sum)}')
    local total_coord_min=$((total_coord / 60000))
    print_msg BLUE "Total coordination time: ${total_coord_min} minutes"

    # Task assignments
    local total_assignments=$(grep '"event":"assign"' "$METRICS_FILE" 2>/dev/null | wc -l | tr -d ' ')
    local total_tasks=$(grep '"event":"assign"' "$METRICS_FILE" | \
        grep -o '"task_count":[0-9]*' | \
        cut -d: -f2 | \
        awk '{sum+=$1} END {print int(sum)}')
    print_msg BLUE "Task assignments: $total_assignments events, $total_tasks tasks total"

    # Threshold checks
    echo ""
    print_msg GREEN "=== Threshold Analysis ==="

    # Weekly coordination time (approximate - need date range)
    local coord_per_week=$((total_coord_min / 1)) # Simplified
    if [[ $coord_per_week -gt 30 ]]; then
        print_msg RED "⚠️  THRESHOLD EXCEEDED: Coordination time >${coord_per_week}min/week"
        print_msg YELLOW "   Recommendation: Build full NTM (broadcast, auto-scale)"
    else
        print_msg GREEN "✓ Coordination time within acceptable range"
    fi

    # Spawn frequency
    if [[ $total_spawns -gt 10 ]]; then
        print_msg YELLOW "⚠️  High swarm usage detected ($total_spawns spawns)"
        print_msg YELLOW "   Consider: Full NTM if coordination becomes bottleneck"
    fi

    # Assignment methods
    echo ""
    print_msg GREEN "=== Assignment Methods ==="
    grep '"event":"assign"' "$METRICS_FILE" | \
        grep -o '"method":"[^"]*"' | \
        cut -d'"' -f4 | \
        sort | uniq -c | sort -rn | \
        awk '{print "  " $2 ": " $1 " assignments"}'

    # Coordination activities
    echo ""
    print_msg GREEN "=== Coordination Activities ==="
    grep '"event":"coordination"' "$METRICS_FILE" | \
        grep -o '"activity":"[^"]*"' | \
        cut -d'"' -f4 | \
        sort | uniq -c | sort -rn | \
        awk '{print "  " $2 ": " $1 " events"}'
}

# Weekly summary
weekly_summary() {
    local week_start=$(date -u -v-7d +"%Y-%m-%d" 2>/dev/null || date -u -d "7 days ago" +"%Y-%m-%d")
    local week_end=$(date -u +"%Y-%m-%d")

    print_msg GREEN "=== Weekly Swarm Summary ($week_start to $week_end) ==="

    if [[ ! -f "$METRICS_FILE" ]]; then
        print_msg YELLOW "No metrics data"
        return
    fi

    # Spawns this week
    local week_spawns=$(grep "^{" "$METRICS_FILE" | \
        jq -r "select(.timestamp >= \"$week_start\" and .timestamp <= \"$week_end\" and .event == \"spawn\")" 2>/dev/null | \
        wc -l | tr -d ' ')

    print_msg BLUE "Swarm spawns this week: $week_spawns"

    # Coordination time this week
    local week_coord=$(grep "^{" "$METRICS_FILE" | \
        jq -r "select(.timestamp >= \"$week_start\" and .event == \"coordination\") | .time_ms" 2>/dev/null | \
        awk '{sum+=$1} END {print int(sum/60000)}')

    print_msg BLUE "Coordination time this week: ${week_coord} minutes"

    if [[ $week_coord -gt 30 ]]; then
        print_msg RED "⚠️  Weekly coordination exceeds 30min threshold!"
    fi
}

# Main
main() {
    local command="${1:-}"

    case "$command" in
        --summary|summary)
            analyze_metrics
            ;;
        --weekly|weekly)
            weekly_summary
            ;;
        --init|init)
            init_metrics
            ;;
        --help|help|-h)
            cat <<EOF
Usage: $0 [COMMAND]

Commands:
  --summary      Show full swarm metrics analysis
  --weekly       Show weekly summary
  --init         Initialize metrics file
  --help         Show this help

Logging Functions:
  spawn <count> <name> <duration_ms>     Log swarm spawn
  assign <task_count> <duration_ms> <method>  Log task assignment
  coord <activity> <time_seconds>        Log coordination overhead

Examples:
  $0 spawn 5 my-swarm 2000
  $0 assign 10 500 round-robin
  $0 coord spawn 120

Integration:
  Call from spawn-swarm.sh, assign-tasks.sh, etc. to track usage

Files:
  Metrics: docs/metrics/swarm-metrics.jsonl

EOF
            ;;
        spawn)
            shift
            log_spawn "$@"
            ;;
        assign)
            shift
            log_assignment "$@"
            ;;
        coord)
            shift
            log_coordination "$@"
            ;;
        *)
            init_metrics
            analyze_metrics
            ;;
    esac
}

main "$@"
