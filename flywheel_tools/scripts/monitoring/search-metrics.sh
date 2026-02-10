#!/usr/bin/env bash
# search-metrics.sh - Track search-history.sh usage and performance
#
# Logs search queries, latency, result counts for Phase 4 evaluation metrics
# Usage: ./scripts/search-metrics.sh [--summary]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
METRICS_DIR="$PROJECT_ROOT/docs/metrics"
METRICS_FILE="$METRICS_DIR/search-metrics.jsonl"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_msg() {
    local color=$1
    shift
    echo -e "${!color}$*${NC}"
}

# Initialize metrics file
init_metrics() {
    mkdir -p "$METRICS_DIR"
    if [[ ! -f "$METRICS_FILE" ]]; then
        echo "# Search metrics log (JSONL format)" > "$METRICS_FILE"
        print_msg GREEN "✓ Initialized $METRICS_FILE"
    fi
}

# Log a search query with metrics
log_search() {
    local query="$1"
    local start_time="$2"
    local end_time="$3"
    local result_count="${4:-0}"
    local sources="${5:-all}"

    local latency_ms=$(( (end_time - start_time) ))
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Create JSON record
    local record=$(cat <<EOF
{"timestamp":"$timestamp","query":"$query","latency_ms":$latency_ms,"result_count":$result_count,"sources":"$sources"}
EOF
)

    echo "$record" >> "$METRICS_FILE"
    print_msg BLUE "Logged search: $latency_ms ms, $result_count results"
}

# Analyze search patterns
analyze_patterns() {
    if [[ ! -f "$METRICS_FILE" ]]; then
        print_msg YELLOW "No metrics data yet"
        return
    fi

    print_msg GREEN "=== Search Metrics Analysis ==="
    echo ""

    # Total queries
    local total=$(grep -c '^{' "$METRICS_FILE" 2>/dev/null || echo 0)
    print_msg BLUE "Total searches: $total"

    if [[ $total -eq 0 ]]; then
        print_msg YELLOW "No search data collected yet"
        return
    fi

    # Average latency
    local avg_latency=$(grep -o '"latency_ms":[0-9]*' "$METRICS_FILE" | \
        cut -d: -f2 | \
        awk '{sum+=$1; count++} END {if (count>0) print int(sum/count); else print 0}')
    print_msg BLUE "Average latency: ${avg_latency} ms"

    # Max latency
    local max_latency=$(grep -o '"latency_ms":[0-9]*' "$METRICS_FILE" | \
        cut -d: -f2 | \
        sort -n | tail -1)
    print_msg BLUE "Max latency: ${max_latency} ms"

    # Average results
    local avg_results=$(grep -o '"result_count":[0-9]*' "$METRICS_FILE" | \
        cut -d: -f2 | \
        awk '{sum+=$1; count++} END {if (count>0) print int(sum/count); else print 0}')
    print_msg BLUE "Average results: ${avg_results}"

    # Threshold checks
    echo ""
    print_msg GREEN "=== Threshold Analysis ==="

    # Check if average latency exceeds 10s (10000ms)
    if [[ $avg_latency -gt 10000 ]]; then
        print_msg RED "⚠️  THRESHOLD EXCEEDED: Average latency >10s"
        print_msg YELLOW "   Recommendation: Build full CASS (semantic search, <60ms)"
    elif [[ $avg_latency -gt 5000 ]]; then
        print_msg YELLOW "⚠️  Warning: Average latency >5s (approaching threshold)"
    else
        print_msg GREEN "✓ Latency within acceptable range (<5s)"
    fi

    # Search frequency
    local searches_per_day=$(echo "$total / 1" | bc) # Simplified - need date range
    print_msg BLUE "Search frequency: ~$searches_per_day total (need time range for per-day calc)"

    if [[ $total -gt 100 ]]; then
        print_msg YELLOW "⚠️  High search volume detected"
        print_msg YELLOW "   Consider: Full CASS if latency becomes bottleneck"
    fi

    # Most common search sources
    echo ""
    print_msg GREEN "=== Source Distribution ==="
    grep -o '"sources":"[^"]*"' "$METRICS_FILE" | \
        cut -d'"' -f4 | \
        sort | uniq -c | sort -rn | \
        awk '{print "  " $2 ": " $1 " queries"}'
}

# Generate weekly summary
weekly_summary() {
    local week_start=$(date -u -v-7d +"%Y-%m-%d" 2>/dev/null || date -u -d "7 days ago" +"%Y-%m-%d")
    local week_end=$(date -u +"%Y-%m-%d")

    print_msg GREEN "=== Weekly Summary ($week_start to $week_end) ==="

    if [[ ! -f "$METRICS_FILE" ]]; then
        print_msg YELLOW "No metrics data"
        return
    fi

    # Filter last 7 days
    local week_queries=$(grep "^{" "$METRICS_FILE" | \
        jq -r "select(.timestamp >= \"$week_start\" and .timestamp <= \"$week_end\")" 2>/dev/null | \
        wc -l | tr -d ' ')

    if [[ $week_queries -eq 0 ]]; then
        print_msg YELLOW "No searches in the last 7 days"
        return
    fi

    print_msg BLUE "Searches this week: $week_queries"
    print_msg BLUE "Searches per day: $(echo "scale=1; $week_queries / 7" | bc)"

    # Week average latency
    local week_avg=$(grep "^{" "$METRICS_FILE" | \
        jq -r "select(.timestamp >= \"$week_start\") | .latency_ms" 2>/dev/null | \
        awk '{sum+=$1; count++} END {if (count>0) print int(sum/count); else print 0}')
    print_msg BLUE "Average latency: ${week_avg} ms"
}

# Main
main() {
    local command="${1:-}"

    case "$command" in
        --summary|summary)
            analyze_patterns
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
  --summary      Show full analysis of search metrics
  --weekly       Show weekly summary
  --init         Initialize metrics file
  --help         Show this help

Integration:
  To track searches, wrap search-history.sh calls:

  start=\$(date +%s%3N)
  results=\$(./scripts/search-history.sh "query")
  end=\$(date +%s%3N)
  count=\$(echo "\$results" | wc -l)
  ./scripts/search-metrics.sh log "query" "\$start" "\$end" "\$count"

Files:
  Metrics: docs/metrics/search-metrics.jsonl

EOF
            ;;
        log)
            shift
            log_search "$@"
            ;;
        *)
            init_metrics
            analyze_patterns
            ;;
    esac
}

main "$@"
