#!/usr/bin/env bash
# fleet-metrics.sh - Track fleet dashboard usage and task completion
#
# Logs task completion, agent activity, reservation patterns for Phase 4 evaluation
# Usage: ./scripts/fleet-metrics.sh [--summary]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
METRICS_DIR="$PROJECT_ROOT/docs/metrics"
METRICS_FILE="$METRICS_DIR/fleet-metrics.jsonl"

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
        echo "# Fleet metrics log (JSONL format)" > "$METRICS_FILE"
        print_msg GREEN "✓ Initialized $METRICS_FILE"
    fi
}

# Capture daily snapshot from fleet dashboard
capture_snapshot() {
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Get fleet data from fleet-core.sh
    local fleet_json
    if [[ -x "$SCRIPT_DIR/fleet-core.sh" ]]; then
        fleet_json=$("$SCRIPT_DIR/fleet-core.sh" aggregate 2>/dev/null || echo '{}')
    else
        fleet_json='{}'
    fi

    # Extract metrics
    local active_agents=$(echo "$fleet_json" | jq -r '.active_agents // 0' 2>/dev/null || echo 0)
    local active_tasks=$(echo "$fleet_json" | jq -r '.tasks.in_progress // 0' 2>/dev/null || echo 0)
    local completed_tasks=$(echo "$fleet_json" | jq -r '.tasks.completed // 0' 2>/dev/null || echo 0)
    local active_reservations=$(echo "$fleet_json" | jq -r '.reservations.active // 0' 2>/dev/null || echo 0)

    local record=$(cat <<EOF
{"timestamp":"$timestamp","active_agents":$active_agents,"active_tasks":$active_tasks,"completed_tasks":$completed_tasks,"active_reservations":$active_reservations}
EOF
)

    echo "$record" >> "$METRICS_FILE"
    print_msg BLUE "Captured snapshot: $active_agents agents, $active_tasks active tasks, $completed_tasks completed"
}

# Log task completion
log_completion() {
    local task_id="$1"
    local duration_hours="${2:-0}"

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local record=$(cat <<EOF
{"timestamp":"$timestamp","event":"task_completed","task_id":"$task_id","duration_hours":$duration_hours}
EOF
)

    echo "$record" >> "$METRICS_FILE"
    print_msg BLUE "Logged task completion: $task_id, ${duration_hours}h"
}

# Analyze fleet metrics
analyze_metrics() {
    if [[ ! -f "$METRICS_FILE" ]]; then
        print_msg YELLOW "No metrics data yet"
        return
    fi

    print_msg GREEN "=== Fleet Metrics Analysis ==="
    echo ""

    # Total snapshots
    local total_snapshots=$(grep -v '^#' "$METRICS_FILE" | grep -c '^{' 2>/dev/null || echo 0)
    print_msg BLUE "Total snapshots: $total_snapshots"

    if [[ $total_snapshots -eq 0 ]]; then
        print_msg YELLOW "No fleet data collected yet"
        return
    fi

    # Average active agents
    local avg_agents=$(grep '"active_agents"' "$METRICS_FILE" | \
        grep -o '"active_agents":[0-9]*' | \
        cut -d: -f2 | \
        awk '{sum+=$1; count++} END {if (count>0) print int(sum/count); else print 0}')
    print_msg BLUE "Average active agents: $avg_agents"

    # Peak active agents
    local peak_agents=$(grep '"active_agents"' "$METRICS_FILE" | \
        grep -o '"active_agents":[0-9]*' | \
        cut -d: -f2 | \
        sort -n | tail -1)
    print_msg BLUE "Peak active agents: $peak_agents"

    # Total completed tasks
    local total_completed=$(grep '"event":"task_completed"' "$METRICS_FILE" 2>/dev/null | wc -l | tr -d ' ')
    print_msg BLUE "Tasks completed (logged): $total_completed"

    # Average task duration
    if [[ $total_completed -gt 0 ]]; then
        local avg_duration=$(grep '"event":"task_completed"' "$METRICS_FILE" | \
            grep -o '"duration_hours":[0-9.]*' | \
            cut -d: -f2 | \
            awk '{sum+=$1; count++} END {if (count>0) printf "%.1f", sum/count; else print 0}')
        print_msg BLUE "Average task duration: ${avg_duration}h"
    fi

    # Average active reservations
    local avg_reservations=$(grep '"active_reservations"' "$METRICS_FILE" | \
        grep -o '"active_reservations":[0-9]*' | \
        cut -d: -f2 | \
        awk '{sum+=$1; count++} END {if (count>0) print int(sum/count); else print 0}')
    print_msg BLUE "Average active reservations: $avg_reservations"

    # Threshold checks
    echo ""
    print_msg GREEN "=== Activity Analysis ==="

    if [[ $peak_agents -gt 10 ]]; then
        print_msg YELLOW "⚠️  High concurrent agent activity detected (peak: $peak_agents)"
        print_msg YELLOW "   Consider: Fleet dashboard optimization if monitoring becomes bottleneck"
    elif [[ $peak_agents -gt 5 ]]; then
        print_msg BLUE "Moderate fleet size (peak: $peak_agents agents)"
    else
        print_msg GREEN "✓ Small fleet size (peak: $peak_agents agents)"
    fi

    if [[ $avg_reservations -gt 20 ]]; then
        print_msg YELLOW "⚠️  High reservation volume (avg: $avg_reservations concurrent)"
    fi
}

# Weekly summary
weekly_summary() {
    local week_start=$(date -u -v-7d +"%Y-%m-%d" 2>/dev/null || date -u -d "7 days ago" +"%Y-%m-%d")
    local week_end=$(date -u +"%Y-%m-%d")

    print_msg GREEN "=== Weekly Fleet Summary ($week_start to $week_end) ==="

    if [[ ! -f "$METRICS_FILE" ]]; then
        print_msg YELLOW "No metrics data"
        return
    fi

    # Completions this week
    local week_completed=$(grep "^{" "$METRICS_FILE" | \
        jq -r "select(.timestamp >= \"$week_start\" and .timestamp <= \"$week_end\" and .event == \"task_completed\")" 2>/dev/null | \
        wc -l | tr -d ' ')

    print_msg BLUE "Tasks completed this week: $week_completed"

    if [[ $week_completed -gt 0 ]]; then
        local tasks_per_day=$(echo "scale=1; $week_completed / 7" | bc)
        print_msg BLUE "Tasks per day: $tasks_per_day"

        # Calculate velocity (tasks per week)
        print_msg BLUE "Weekly velocity: $week_completed tasks/week"
    fi

    # Peak agents this week
    local week_peak=$(grep "^{" "$METRICS_FILE" | \
        jq -r "select(.timestamp >= \"$week_start\") | .active_agents" 2>/dev/null | \
        sort -n | tail -1)

    if [[ -n "$week_peak" && "$week_peak" != "null" ]]; then
        print_msg BLUE "Peak agents this week: $week_peak"
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
        --snapshot|snapshot)
            capture_snapshot
            ;;
        --init|init)
            init_metrics
            ;;
        --help|help|-h)
            cat <<EOF
Usage: $0 [COMMAND]

Commands:
  --summary      Show full fleet metrics analysis
  --weekly       Show weekly summary
  --snapshot     Capture current fleet state
  --init         Initialize metrics file
  --help         Show this help

Logging Functions:
  complete <task_id> <duration_hours>   Log task completion

Examples:
  $0 snapshot                    # Daily snapshot (run via cron)
  $0 complete bd-123 4.5        # Log 4.5 hour task completion

Integration:
  - Add to crontab for daily snapshots: 0 0 * * * /path/to/fleet-metrics.sh snapshot
  - Call from task completion workflows

Files:
  Metrics: docs/metrics/fleet-metrics.jsonl

EOF
            ;;
        complete)
            shift
            log_completion "$@"
            ;;
        *)
            init_metrics
            analyze_metrics
            ;;
    esac
}

main "$@"
