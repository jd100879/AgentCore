#!/usr/bin/env bash
# metrics-summary.sh - Aggregate all Phase 3 metrics and generate reports
#
# Combines search, swarm, and fleet metrics for evaluation period analysis
# Usage: ./scripts/metrics-summary.sh [--weekly|--full|--thresholds]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
METRICS_DIR="$PROJECT_ROOT/docs/metrics"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

print_msg() {
    local color=$1
    shift
    echo -e "${!color}$*${NC}"
}

print_header() {
    echo ""
    print_msg CYAN "═══════════════════════════════════════════════════════"
    print_msg CYAN "  $1"
    print_msg CYAN "═══════════════════════════════════════════════════════"
    echo ""
}

# Initialize all metrics
init_all() {
    print_header "Initializing Metrics Collection"

    "$SCRIPT_DIR/search-metrics.sh" init
    "$SCRIPT_DIR/swarm-metrics.sh" init
    "$SCRIPT_DIR/fleet-metrics.sh" init

    print_msg GREEN "✓ All metrics initialized"
    echo ""
    print_msg BLUE "Metrics will be stored in: $METRICS_DIR"
    print_msg BLUE "- search-metrics.jsonl (search queries and latency)"
    print_msg BLUE "- swarm-metrics.jsonl (swarm usage and coordination)"
    print_msg BLUE "- fleet-metrics.jsonl (fleet snapshots and task completion)"
}

# Full summary across all metrics
full_summary() {
    print_header "Phase 3 Metrics - Full Summary"

    # Search metrics
    if [[ -f "$METRICS_DIR/search-metrics.jsonl" ]]; then
        print_msg MAGENTA ">>> Search Performance"
        "$SCRIPT_DIR/search-metrics.sh" summary
        echo ""
    else
        print_msg YELLOW "No search metrics yet"
    fi

    # Swarm metrics
    if [[ -f "$METRICS_DIR/swarm-metrics.jsonl" ]]; then
        print_msg MAGENTA ">>> Swarm Orchestration"
        "$SCRIPT_DIR/swarm-metrics.sh" summary
        echo ""
    else
        print_msg YELLOW "No swarm metrics yet"
    fi

    # Fleet metrics
    if [[ -f "$METRICS_DIR/fleet-metrics.jsonl" ]]; then
        print_msg MAGENTA ">>> Fleet Activity"
        "$SCRIPT_DIR/fleet-metrics.sh" summary
        echo ""
    else
        print_msg YELLOW "No fleet metrics yet"
    fi
}

# Weekly summary
weekly_summary() {
    local week_start=$(date -u -v-7d +"%Y-%m-%d" 2>/dev/null || date -u -d "7 days ago" +"%Y-%m-%d")
    local week_end=$(date -u +"%Y-%m-%d")

    print_header "Phase 3 Metrics - Weekly Summary ($week_start to $week_end)"

    if [[ -f "$METRICS_DIR/search-metrics.jsonl" ]]; then
        "$SCRIPT_DIR/search-metrics.sh" weekly
        echo ""
    fi

    if [[ -f "$METRICS_DIR/swarm-metrics.jsonl" ]]; then
        "$SCRIPT_DIR/swarm-metrics.sh" weekly
        echo ""
    fi

    if [[ -f "$METRICS_DIR/fleet-metrics.jsonl" ]]; then
        "$SCRIPT_DIR/fleet-metrics.sh" weekly
        echo ""
    fi

    # Overall assessment
    print_header "Weekly Assessment"
    assess_thresholds "weekly"
}

# Check all thresholds and provide recommendations
assess_thresholds() {
    local period="${1:-full}" # weekly or full

    print_msg GREEN "=== Phase 4 Decision Thresholds ==="
    echo ""

    local recommendations=()
    local all_ok=true

    # Search latency threshold
    if [[ -f "$METRICS_DIR/search-metrics.jsonl" ]]; then
        local avg_latency=$(grep -o '"latency_ms":[0-9]*' "$METRICS_DIR/search-metrics.jsonl" | \
            cut -d: -f2 | \
            awk '{sum+=$1; count++} END {if (count>0) print int(sum/count); else print 0}')

        if [[ $avg_latency -gt 10000 ]]; then
            print_msg RED "❌ SEARCH: Average latency ${avg_latency}ms (>10s threshold)"
            recommendations+=("Build Full CASS (semantic search, <60ms performance)")
            all_ok=false
        elif [[ $avg_latency -gt 5000 ]]; then
            print_msg YELLOW "⚠️  SEARCH: Average latency ${avg_latency}ms (approaching threshold)"
        else
            print_msg GREEN "✓ SEARCH: Average latency ${avg_latency}ms (within limits)"
        fi
    else
        print_msg BLUE "○ SEARCH: No data collected"
    fi

    # Swarm coordination threshold
    if [[ -f "$METRICS_DIR/swarm-metrics.jsonl" ]]; then
        local total_coord=$(grep '"event":"coordination"' "$METRICS_DIR/swarm-metrics.jsonl" | \
            grep -o '"time_ms":[0-9]*' | \
            cut -d: -f2 | \
            awk '{sum+=$1} END {print int(sum/60000)}') # Convert to minutes

        # Rough weekly estimate (divide by number of weeks)
        local coord_weekly=$total_coord # Simplified - need date range

        if [[ $coord_weekly -gt 30 ]]; then
            print_msg RED "❌ SWARM: Coordination ~${coord_weekly}min total (>30min/week threshold)"
            recommendations+=("Build Full NTM (broadcast, auto-scale, mixed agents)")
            all_ok=false
        else
            print_msg GREEN "✓ SWARM: Coordination ${coord_weekly}min total (within limits)"
        fi
    else
        print_msg BLUE "○ SWARM: No data collected"
    fi

    # Task complexity threshold
    local task_count=$(br list 2>/dev/null | grep -c '^' || echo 0)
    if [[ $task_count -gt 50 ]]; then
        print_msg YELLOW "⚠️  TASKS: $task_count tasks (>50 threshold for graph visualization)"
        recommendations+=("Consider Beads TUI (graph viz, dependency metrics)")
    else
        print_msg GREEN "✓ TASKS: $task_count tasks (CLI adequate)"
    fi

    # Fleet size
    if [[ -f "$METRICS_DIR/fleet-metrics.jsonl" ]]; then
        local peak_agents=$(grep '"active_agents"' "$METRICS_DIR/fleet-metrics.jsonl" | \
            grep -o '"active_agents":[0-9]*' | \
            cut -d: -f2 | \
            sort -n | tail -1)

        if [[ $peak_agents -gt 10 ]]; then
            print_msg YELLOW "⚠️  FLEET: Peak $peak_agents agents (high concurrency)"
        else
            print_msg GREEN "✓ FLEET: Peak $peak_agents agents (manageable size)"
        fi
    else
        print_msg BLUE "○ FLEET: No data collected"
    fi

    # Overall recommendation
    echo ""
    print_msg GREEN "=== Recommendations ==="
    echo ""

    if [[ $all_ok == true && ${#recommendations[@]} -eq 0 ]]; then
        print_msg GREEN "✓ All thresholds within acceptable range"
        print_msg GREEN "✓ Continue with Phase 3 tools"
        print_msg BLUE "▸ Revisit after $(( (8 - 1) )) more weeks of data collection"
    else
        print_msg YELLOW "Phase 4 features triggered by evidence:"
        for rec in "${recommendations[@]}"; do
            print_msg YELLOW "  • $rec"
        done
    fi

}

# Generate markdown report
generate_report() {
    local output_file="$METRICS_DIR/weekly-report-$(date +%Y-%m-%d).md"

    print_header "Generating Weekly Report"

    cat > "$output_file" <<EOF
# Phase 3 Metrics - Weekly Report

**Period:** $(date -u -v-7d +"%Y-%m-%d" 2>/dev/null || date -u -d "7 days ago" +"%Y-%m-%d") to $(date -u +"%Y-%m-%d")
**Generated:** $(date -u +"%Y-%m-%d %H:%M:%S UTC")

---

## Search Performance

EOF

    if [[ -f "$METRICS_DIR/search-metrics.jsonl" ]]; then
        "$SCRIPT_DIR/search-metrics.sh" weekly >> "$output_file"
    else
        echo "No search data collected." >> "$output_file"
    fi

    cat >> "$output_file" <<EOF

---

## Swarm Orchestration

EOF

    if [[ -f "$METRICS_DIR/swarm-metrics.jsonl" ]]; then
        "$SCRIPT_DIR/swarm-metrics.sh" weekly >> "$output_file"
    else
        echo "No swarm data collected." >> "$output_file"
    fi

    cat >> "$output_file" <<EOF

---

## Fleet Activity

EOF

    if [[ -f "$METRICS_DIR/fleet-metrics.jsonl" ]]; then
        "$SCRIPT_DIR/fleet-metrics.sh" weekly >> "$output_file"
    else
        echo "No fleet data collected." >> "$output_file"
    fi

    cat >> "$output_file" <<EOF

---

## Phase 4 Decision Assessment

EOF

    assess_thresholds weekly >> "$output_file"

    cat >> "$output_file" <<EOF

---

**Next Review:** $(date -u -v+7d +"%Y-%m-%d" 2>/dev/null || date -u -d "7 days" +"%Y-%m-%d")
**Phase 4 Decision:** After 4-8 weeks of evaluation (early March 2026)

EOF

    print_msg GREEN "✓ Report generated: $output_file"
}

# Main
main() {
    local command="${1:-summary}"

    case "$command" in
        --init|init)
            init_all
            ;;
        --full|full)
            full_summary
            assess_thresholds full
            ;;
        --weekly|weekly)
            weekly_summary
            ;;
        --thresholds|thresholds)
            print_header "Phase 4 Decision Thresholds"
            assess_thresholds full
            ;;
        --report|report)
            generate_report
            ;;
        --help|help|-h)
            cat <<EOF
Usage: $0 [COMMAND]

Commands:
  --init         Initialize all metrics collection
  --full         Show full summary across all metrics
  --weekly       Show weekly summary
  --thresholds   Check Phase 4 decision thresholds
  --report       Generate markdown weekly report
  --help         Show this help

Phase 4 Decision Thresholds:
  - Search >10s latency → Build Full CASS
  - Coordination >30min/week → Build Full NTM
  - >50 active tasks → Build Beads TUI
  - >2 teams request → Build Multi-repo

Files:
  Metrics: docs/metrics/*.jsonl
  Reports: docs/metrics/weekly-report-*.md

Automation:
  # Daily snapshot (add to crontab)
  0 0 * * * $SCRIPT_DIR/fleet-metrics.sh snapshot

  # Weekly report (add to crontab)
  0 9 * * 1 $SCRIPT_DIR/metrics-summary.sh report

EOF
            ;;
        summary|--summary|*)
            full_summary
            assess_thresholds full
            ;;
    esac
}

main "$@"
