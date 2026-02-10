#!/usr/bin/env bash
# ntm-dashboard.sh - Unified NTM (Near-Term Memory) Dashboard
#
# Usage:
#   ./scripts/ntm-dashboard.sh              # Full dashboard
#   ./scripts/ntm-dashboard.sh --section <name>  # Specific section only
#   ./scripts/ntm-dashboard.sh --compact    # One-line summary
#   ./scripts/ntm-dashboard.sh --json       # JSON output
#   ./scripts/ntm-dashboard.sh --watch      # Auto-refresh mode
#
# Part of: bd-25o - Phase 1 NTM Integration & Polish

set -euo pipefail

# Project root and paths
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTO_SCALER="$PROJECT_ROOT/scripts/auto-scaler.sh"
AGENT_REGISTRY="$PROJECT_ROOT/scripts/agent-registry.sh"
QUEUE_MONITOR="$PROJECT_ROOT/scripts/queue-monitor.sh"
MATCH_ENGINE="$PROJECT_ROOT/scripts/match-engine.sh"
PERFORMANCE_TRACKER="$PROJECT_ROOT/scripts/performance-tracker.sh"
QUALITY_SCORER="$PROJECT_ROOT/scripts/bead-quality-scorer.sh"
NTM_CONFIG="$PROJECT_ROOT/.beads/ntm-config.yaml"
SWARM_STATUS="$PROJECT_ROOT/scripts/swarm-status.sh"

# Default configuration
WATCH_INTERVAL=5
DEFAULT_SECTIONS="all"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

#######################################
# Print colored message
#######################################
print_msg() {
    local color="${!1}"
    local msg="$2"
    echo -e "${color}${msg}${NC}"
}

#######################################
# Print section header
#######################################
print_header() {
    local title="$1"
    echo ""
    echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    printf "${BOLD}${BLUE}║${NC} %-68s ${BOLD}${BLUE}║${NC}\n" "$title"
    echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════════════════════╝${NC}"
}

#######################################
# Print subsection header
#######################################
print_subheader() {
    local title="$1"
    echo ""
    echo -e "${BOLD}${CYAN}▸ $title${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────────${NC}"
}

#######################################
# Get queue status
#######################################
get_queue_status() {
    if [ ! -f "$AUTO_SCALER" ]; then
        echo "{\"error\": \"auto-scaler.sh not found\"}"
        return 1
    fi

    # Get JSON output from auto-scaler
    local analysis=$("$AUTO_SCALER" analyze 2>/dev/null | sed -n '/{/,/^}/p' || echo '{}')
    echo "$analysis"
}

#######################################
# Get agent registry status
#######################################
get_agent_registry_status() {
    if [ ! -f "$AGENT_REGISTRY" ]; then
        echo "{\"error\": \"agent-registry.sh not found\"}"
        return 1
    fi

    # Get active agents
    local active_count=$("$AGENT_REGISTRY" active 2>/dev/null | grep -c "^" || echo "0")

    # Get available types
    local types_output=$("$AGENT_REGISTRY" list 2>/dev/null | grep -E "^  [a-z]+" | awk '{print $1}' | tr '\n' ',' | sed 's/,$//' || echo "")

    cat <<EOF
{
  "active_agents": $active_count,
  "available_types": "${types_output}"
}
EOF
}

#######################################
# Get queue monitor status
#######################################
get_monitor_status() {
    if [ ! -f "$QUEUE_MONITOR" ]; then
        echo "{\"error\": \"queue-monitor.sh not found\"}"
        return 1
    fi

    # Check if monitor is running
    local status_output=$("$QUEUE_MONITOR" status 2>&1 || echo "stopped")

    if echo "$status_output" | grep -q "running"; then
        echo "{\"status\": \"running\", \"healthy\": true}"
    else
        echo "{\"status\": \"stopped\", \"healthy\": false}"
    fi
}

#######################################
# Get performance metrics
#######################################
get_performance_metrics() {
    if [ ! -f "$PERFORMANCE_TRACKER" ]; then
        echo "{\"error\": \"performance-tracker.sh not found (bd-3si in progress)\"}"
        return 1
    fi

    # Get performance data file
    local perf_file="$PROJECT_ROOT/.beads/agent-performance.jsonl"

    if [ ! -f "$perf_file" ] || [ ! -s "$perf_file" ]; then
        echo '{"tasks_completed": 0, "avg_cycle_time": 0, "note": "No performance data yet"}'
        return 0
    fi

    # Calculate summary metrics from performance file
    local total_tasks=$(wc -l < "$perf_file" | tr -d ' ')
    local avg_duration=$(jq -s 'map(select(.duration != null)) | if length > 0 then (map(.duration) | add / length) else 0 end' "$perf_file" 2>/dev/null || echo "0")

    cat <<EOF
{
  "tasks_completed": $total_tasks,
  "avg_cycle_time": $(printf "%.0f" "$avg_duration")
}
EOF
}

#######################################
# Get quality metrics
#######################################
get_quality_metrics() {
    if [ ! -f "$QUALITY_SCORER" ]; then
        echo '{"error": "bead-quality-scorer.sh not found (bd-1i44 in progress)"}'
        return 1
    fi

    # Get stats from quality scorer
    local quality_stats=$("$QUALITY_SCORER" stats 2>/dev/null || echo '{}')
    echo "$quality_stats"
}

#######################################
# Get active swarms
#######################################
get_active_swarms() {
    local pids_dir="$PROJECT_ROOT/pids"

    if [ ! -d "$pids_dir" ]; then
        echo "[]"
        return 0
    fi

    # Find all swarm state files
    local swarms=$(find "$pids_dir" -name "swarm-*.state" -type f 2>/dev/null || echo "")

    if [ -z "$swarms" ]; then
        echo "[]"
        return 0
    fi

    # Build JSON array
    echo "["
    local first=true
    while IFS= read -r state_file; do
        if [ -f "$state_file" ]; then
            if [ "$first" = false ]; then
                echo ","
            fi
            first=false

            local session_name=$(basename "$state_file" .state | sed 's/^swarm-//')
            local agent_count=$(jq -r '.agents | length' "$state_file" 2>/dev/null || echo "0")

            cat <<EOF
  {
    "session": "$session_name",
    "agents": $agent_count
  }
EOF
        fi
    done <<< "$swarms"
    echo "]"
}

#######################################
# Display queue section
#######################################
display_queue_section() {
    print_subheader "Queue Status"

    local queue_data=$(get_queue_status)

    if echo "$queue_data" | jq -e '.error' >/dev/null 2>&1; then
        print_msg RED "  Error: $(echo "$queue_data" | jq -r '.error')"
        return 1
    fi

    local ready_tasks=$(echo "$queue_data" | jq -r '.ready_tasks')
    local active_agents=$(echo "$queue_data" | jq -r '.active_agents')
    local ratio=$(echo "$queue_data" | jq -r '.ratio')

    echo "  Ready Tasks: $ready_tasks"
    echo "  Active Agents: $active_agents"
    printf "  Tasks/Agent Ratio: %.2f\n" "$ratio"

    # Show types needed
    local types_needed=$(echo "$queue_data" | jq -r '.types_needed | to_entries[] | "    \(.key): \(.value)"' 2>/dev/null || echo "")
    if [ -n "$types_needed" ]; then
        echo ""
        echo "  Types Needed:"
        echo "$types_needed"
    fi

    # Show recommendations
    local recommendations=$(echo "$queue_data" | jq -r '.recommendations[]' 2>/dev/null || echo "")
    if [ -n "$recommendations" ]; then
        echo ""
        echo "  Recommendations:"
        echo "$recommendations" | while IFS= read -r rec; do
            if echo "$rec" | grep -q "scale-up"; then
                print_msg GREEN "    ↑ $rec"
            elif echo "$rec" | grep -q "scale-down"; then
                print_msg YELLOW "    ↓ $rec"
            else
                echo "    • $rec"
            fi
        done
    fi
}

#######################################
# Display agents section
#######################################
display_agents_section() {
    print_subheader "Agent Registry"

    local agent_data=$(get_agent_registry_status)

    if echo "$agent_data" | jq -e '.error' >/dev/null 2>&1; then
        print_msg RED "  Error: $(echo "$agent_data" | jq -r '.error')"
        return 1
    fi

    local active_count=$(echo "$agent_data" | jq -r '.active_agents')
    local types=$(echo "$agent_data" | jq -r '.available_types')

    echo "  Active Agents: $active_count"
    echo "  Available Types: $types"

    # List active agents if registry supports it
    if [ -f "$AGENT_REGISTRY" ]; then
        echo ""
        echo "  Agent Instances:"
        "$AGENT_REGISTRY" active 2>/dev/null | sed 's/^/    /' || echo "    (no active agents)"
    fi
}

#######################################
# Display monitor section
#######################################
display_monitor_section() {
    print_subheader "Queue Monitor"

    local monitor_data=$(get_monitor_status)

    if echo "$monitor_data" | jq -e '.error' >/dev/null 2>&1; then
        print_msg YELLOW "  Warning: $(echo "$monitor_data" | jq -r '.error')"
        return 0
    fi

    local status=$(echo "$monitor_data" | jq -r '.status')
    local healthy=$(echo "$monitor_data" | jq -r '.healthy')

    if [ "$status" = "running" ]; then
        print_msg GREEN "  Status: Running ✓"
    else
        print_msg YELLOW "  Status: Stopped"
    fi

    if [ "$healthy" = "true" ]; then
        echo "  Health: Healthy"
    else
        echo "  Health: Degraded"
    fi
}

#######################################
# Display swarms section
#######################################
display_swarms_section() {
    print_subheader "Active Swarms"

    local swarms_data=$(get_active_swarms)
    local swarm_count=$(echo "$swarms_data" | jq '. | length')

    if [ "$swarm_count" -eq 0 ]; then
        echo "  No active swarms"
        return 0
    fi

    echo "  Total Swarms: $swarm_count"
    echo ""

    echo "$swarms_data" | jq -r '.[] | "  • \(.session): \(.agents) agent(s)"'
}

#######################################
# Display performance section
#######################################
display_performance_section() {
    print_subheader "Performance Metrics"

    local perf_data=$(get_performance_metrics)

    if echo "$perf_data" | jq -e '.error' >/dev/null 2>&1; then
        print_msg YELLOW "  $(echo "$perf_data" | jq -r '.error')"
        return 0
    fi

    local tasks_completed=$(echo "$perf_data" | jq -r '.tasks_completed // 0')
    local avg_cycle_time=$(echo "$perf_data" | jq -r '.avg_cycle_time // 0')

    echo "  Tasks Completed: $tasks_completed"
    echo "  Avg Cycle Time: ${avg_cycle_time}s"
}

#######################################
# Display quality section
#######################################
display_quality_section() {
    print_subheader "Task Quality Metrics"

    local quality_data=$(get_quality_metrics)

    if echo "$quality_data" | jq -e '.error' >/dev/null 2>&1; then
        print_msg YELLOW "  $(echo "$quality_data" | jq -r '.error')"
        return 0
    fi

    local total_tasks=$(echo "$quality_data" | jq -r '.total_tasks // 0')
    local avg_quality=$(echo "$quality_data" | jq -r '.avg_quality // 0')
    local low_quality_count=$(echo "$quality_data" | jq -r '.low_quality_count // 0')
    local trend=$(echo "$quality_data" | jq -r '.trend // "unknown"')

    echo "  Tasks Scored: $total_tasks"
    printf "  Avg Quality: %.2f/1.00\n" "$avg_quality"
    echo "  Low Quality Count: $low_quality_count"

    # Display trend with color
    if [ "$trend" = "improving" ]; then
        print_msg GREEN "  Trend: ↑ Improving"
    elif [ "$trend" = "declining" ]; then
        print_msg YELLOW "  Trend: ↓ Declining"
    else
        echo "  Trend: → Stable"
    fi
}

#######################################
# Display compact summary
#######################################
display_compact() {
    local queue_data=$(get_queue_status)
    local agent_data=$(get_agent_registry_status)
    local monitor_data=$(get_monitor_status)

    local ready_tasks=$(echo "$queue_data" | jq -r '.ready_tasks // 0')
    local active_agents=$(echo "$agent_data" | jq -r '.active_agents // 0')
    local monitor_status=$(echo "$monitor_data" | jq -r '.status // "unknown"')

    local status_icon="●"
    if [ "$monitor_status" = "running" ]; then
        status_icon="${GREEN}●${NC}"
    else
        status_icon="${YELLOW}○${NC}"
    fi

    echo -e "NTM: $status_icon | Tasks: $ready_tasks | Agents: $active_agents | Ratio: $(echo "scale=1; $ready_tasks / ($active_agents + 0.1)" | bc)"
}

#######################################
# Display JSON output
#######################################
display_json() {
    local queue_data=$(get_queue_status)
    local agent_data=$(get_agent_registry_status)
    local monitor_data=$(get_monitor_status)
    local swarms_data=$(get_active_swarms)
    local perf_data=$(get_performance_metrics)
    local quality_data=$(get_quality_metrics)

    cat <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "queue": $queue_data,
  "agents": $agent_data,
  "monitor": $monitor_data,
  "swarms": $swarms_data,
  "performance": $perf_data,
  "quality": $quality_data
}
EOF
}

#######################################
# Display full dashboard
#######################################
display_full() {
    print_header "NTM Dashboard - $(date '+%Y-%m-%d %H:%M:%S')"

    display_queue_section
    display_agents_section
    display_monitor_section
    display_swarms_section
    display_performance_section
    display_quality_section

    echo ""
    print_msg CYAN "──────────────────────────────────────────────────────────────────────"
    echo ""
}

#######################################
# Print usage
#######################################
usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Display unified NTM (Near-Term Memory) dashboard aggregating queue status,
agent registry, monitor health, swarms, performance, and quality metrics.

Options:
  --section <name>  Display specific section only (queue|agents|monitor|swarms|performance|quality)
  --compact         One-line summary mode
  --json            JSON output for scripting
  --watch           Auto-refresh every ${WATCH_INTERVAL}s (Ctrl+C to exit)
  --help            Show this help message

Examples:
  $(basename "$0")                          # Full dashboard
  $(basename "$0") --section queue          # Queue status only
  $(basename "$0") --compact                # One-line summary
  $(basename "$0") --watch                  # Auto-refresh mode
  $(basename "$0") --json | jq .            # JSON output

Part of: bd-25o - Phase 1 NTM Integration & Polish
EOF
}

#######################################
# Main function
#######################################
main() {
    local mode="full"
    local section=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --section)
                if [ $# -lt 2 ]; then
                    print_msg RED "Error: --section requires a value"
                    usage
                    exit 1
                fi
                mode="section"
                section="$2"
                shift 2
                ;;
            --compact)
                mode="compact"
                shift
                ;;
            --json)
                mode="json"
                shift
                ;;
            --watch)
                mode="watch"
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                print_msg RED "Error: Unknown option '$1'"
                usage
                exit 1
                ;;
        esac
    done

    # Execute based on mode
    case "$mode" in
        full)
            display_full
            ;;
        compact)
            display_compact
            ;;
        json)
            display_json
            ;;
        watch)
            while true; do
                clear
                display_full
                sleep "$WATCH_INTERVAL"
            done
            ;;
        section)
            case "$section" in
                queue)
                    display_queue_section
                    ;;
                agents)
                    display_agents_section
                    ;;
                monitor)
                    display_monitor_section
                    ;;
                swarms)
                    display_swarms_section
                    ;;
                performance)
                    display_performance_section
                    ;;
                quality)
                    display_quality_section
                    ;;
                *)
                    print_msg RED "Error: Unknown section '$section'"
                    echo "Valid sections: queue, agents, monitor, swarms, performance, quality"
                    exit 1
                    ;;
            esac
            ;;
    esac
}

main "$@"
