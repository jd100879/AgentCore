#!/usr/bin/env bash
# bead-quality-scorer.sh - Task Quality Metrics Tracker
#
# Usage:
#   ./scripts/bead-quality-scorer.sh score <task_id>     # Score a task
#   ./scripts/bead-quality-scorer.sh report              # Show quality report
#   ./scripts/bead-quality-scorer.sh stats               # Summary statistics
#   ./scripts/bead-quality-scorer.sh warn <task_id>      # Check if task is low quality
#
# Part of: bd-1i44 - Add bead quality metrics tracking
# Enhancement to bd-3si (Performance Tracker)

set -euo pipefail

# Project root and paths
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUALITY_REPORTS="$PROJECT_ROOT/.beads/quality-reports.jsonl"
ISSUES_FILE="$PROJECT_ROOT/.beads/issues.jsonl"

# Quality thresholds
LOW_QUALITY_THRESHOLD=0.5
MEDIUM_QUALITY_THRESHOLD=0.7

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
# Get task data from beads
#######################################
get_task_data() {
    local task_id="$1"

    if [ ! -f "$ISSUES_FILE" ]; then
        echo "{\"error\": \"issues.jsonl not found\"}"
        return 1
    fi

    # Get task JSON
    local task_json=$(jq -c "select(.id == \"$task_id\")" "$ISSUES_FILE" 2>/dev/null)

    if [ -z "$task_json" ]; then
        echo "{\"error\": \"Task $task_id not found\"}"
        return 1
    fi

    echo "$task_json"
}

#######################################
# Score a task based on quality metrics
#######################################
score_task() {
    local task_id="$1"

    # Get task data
    local task_json=$(get_task_data "$task_id")

    if echo "$task_json" | jq -e '.error' >/dev/null 2>&1; then
        print_msg RED "Error: $(echo "$task_json" | jq -r '.error')"
        return 1
    fi

    local description=$(echo "$task_json" | jq -r '.description // ""')
    local title=$(echo "$task_json" | jq -r '.title // ""')

    # Initialize scores
    local has_acceptance_criteria=0
    local has_test_plan=0
    local has_complexity_estimate=0

    # Check for acceptance criteria
    # Look for common patterns: "Success Criteria", "Acceptance Criteria", "Definition of Done", checklist items
    if echo "$description" | grep -qiE '(success criteria|acceptance criteria|definition of done|deliverables:|## Tasks|## Success)'; then
        has_acceptance_criteria=1
    fi

    # Check for test plan
    # Look for: "Testing", "Test Plan", "Validation", test scenarios
    if echo "$description" | grep -qiE '(test plan|testing:|validation:|## Testing|verify|test scenarios)'; then
        has_test_plan=1
    fi

    # Check for complexity estimate
    # Look for: "Timeline", "Effort", "Complexity", time estimates, story points
    if echo "$description" | grep -qiE '(timeline:|effort:|complexity:|## Timeline|[0-9]+ (day|week|hour|point)s?)'; then
        has_complexity_estimate=1
    fi

    # Calculate quality score (0.0 - 1.0)
    local quality_score=$(echo "scale=2; ($has_acceptance_criteria + $has_test_plan + $has_complexity_estimate) / 3" | bc)

    # Determine quality level
    local quality_level="low"
    if (( $(echo "$quality_score >= $MEDIUM_QUALITY_THRESHOLD" | bc -l) )); then
        quality_level="high"
    elif (( $(echo "$quality_score >= $LOW_QUALITY_THRESHOLD" | bc -l) )); then
        quality_level="medium"
    fi

    # Create quality report entry
    local report_entry=$(cat <<EOF
{
  "task_id": "$task_id",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "quality_score": $quality_score,
  "quality_level": "$quality_level",
  "metrics": {
    "has_acceptance_criteria": $has_acceptance_criteria,
    "has_test_plan": $has_test_plan,
    "has_complexity_estimate": $has_complexity_estimate
  },
  "title": $(echo "$title" | jq -Rs .)
}
EOF
)

    # Append to quality reports
    echo "$report_entry" >> "$QUALITY_REPORTS"

    # Display result
    print_msg CYAN "Quality Score for $task_id:"
    echo "  Title: $title"
    echo "  Score: $quality_score ($quality_level)"
    echo ""
    echo "  Metrics:"
    [ $has_acceptance_criteria -eq 1 ] && echo "    ✓ Has acceptance criteria" || echo "    ✗ Missing acceptance criteria"
    [ $has_test_plan -eq 1 ] && echo "    ✓ Has test plan" || echo "    ✗ Missing test plan"
    [ $has_complexity_estimate -eq 1 ] && echo "    ✓ Has complexity estimate" || echo "    ✗ Missing complexity estimate"

    echo "$quality_score"
}

#######################################
# Check if task is low quality and warn
#######################################
warn_low_quality() {
    local task_id="$1"

    # Score the task
    local quality_score=$(score_task "$task_id" | tail -1)

    # Check threshold
    if (( $(echo "$quality_score < $LOW_QUALITY_THRESHOLD" | bc -l) )); then
        echo ""
        print_msg YELLOW "⚠️  WARNING: Task $task_id has low quality score ($quality_score < $LOW_QUALITY_THRESHOLD)"
        echo ""
        echo "Consider adding:"
        echo "  - Clear acceptance criteria or success metrics"
        echo "  - Test plan or validation approach"
        echo "  - Timeline or complexity estimate"
        echo ""
        return 1
    else
        print_msg GREEN "✓ Task $task_id meets quality threshold ($quality_score >= $LOW_QUALITY_THRESHOLD)"
        return 0
    fi
}

#######################################
# Show quality report
#######################################
show_report() {
    if [ ! -f "$QUALITY_REPORTS" ] || [ ! -s "$QUALITY_REPORTS" ]; then
        print_msg YELLOW "No quality reports available yet"
        return 0
    fi

    print_msg CYAN "${BOLD}Task Quality Report${NC}"
    echo ""

    # Recent scores
    echo "Recent Scores:"
    jq -r '"\(.task_id): \(.quality_score) (\(.quality_level)) - \(.title)"' "$QUALITY_REPORTS" | tail -10 | sed 's/^/  /'
    echo ""

    # Quality distribution
    local total=$(wc -l < "$QUALITY_REPORTS" | tr -d ' ')
    local low=$(jq 'select(.quality_level == "low")' "$QUALITY_REPORTS" | wc -l | tr -d ' ')
    local medium=$(jq 'select(.quality_level == "medium")' "$QUALITY_REPORTS" | wc -l | tr -d ' ')
    local high=$(jq 'select(.quality_level == "high")' "$QUALITY_REPORTS" | wc -l | tr -d ' ')

    echo "Quality Distribution (Total: $total):"
    echo "  Low    (<0.5): $low"
    echo "  Medium (0.5-0.7): $medium"
    echo "  High   (>0.7): $high"
}

#######################################
# Show summary statistics
#######################################
show_stats() {
    if [ ! -f "$QUALITY_REPORTS" ] || [ ! -s "$QUALITY_REPORTS" ]; then
        echo '{"total_tasks": 0, "avg_quality": 0, "low_quality_count": 0, "trend": "no data"}'
        return 0
    fi

    # Calculate statistics
    local total=$(wc -l < "$QUALITY_REPORTS" | tr -d ' ')
    local avg_quality=$(jq -s 'map(.quality_score) | add / length' "$QUALITY_REPORTS" 2>/dev/null || echo "0")
    local low_quality_count=$(jq 'select(.quality_score < 0.5)' "$QUALITY_REPORTS" | wc -l | tr -d ' ')

    # Calculate trend (last 5 vs previous 5)
    local recent_avg=$(jq -s '.[-5:] | map(.quality_score) | add / length' "$QUALITY_REPORTS" 2>/dev/null || echo "0")
    local previous_avg=$(jq -s '.[-10:-5] | map(.quality_score) | add / length' "$QUALITY_REPORTS" 2>/dev/null || echo "0")

    local trend="stable"
    if (( $(echo "$recent_avg > $previous_avg + 0.1" | bc -l) )); then
        trend="improving"
    elif (( $(echo "$recent_avg < $previous_avg - 0.1" | bc -l) )); then
        trend="declining"
    fi

    # Output JSON
    cat <<EOF
{
  "total_tasks": $total,
  "avg_quality": $(printf "%.2f" "$avg_quality"),
  "low_quality_count": $low_quality_count,
  "recent_avg": $(printf "%.2f" "$recent_avg"),
  "previous_avg": $(printf "%.2f" "$previous_avg"),
  "trend": "$trend"
}
EOF
}

#######################################
# Print usage
#######################################
usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [arguments]

Commands:
  score <task_id>    Score a task based on quality metrics
  warn <task_id>     Check if task is low quality and warn
  report             Show quality report for all scored tasks
  stats              Show summary statistics (JSON format)

Quality Metrics:
  - Has acceptance criteria (0/1)
  - Has test plan (0/1)
  - Has complexity estimate (0/1)
  - Quality Score: sum/3 (0.0 - 1.0)

Quality Levels:
  - Low:    < 0.5
  - Medium: 0.5 - 0.7
  - High:   > 0.7

Examples:
  $(basename "$0") score bd-1i44          # Score task bd-1i44
  $(basename "$0") warn bd-1i44           # Warn if bd-1i44 is low quality
  $(basename "$0") report                 # Show quality report
  $(basename "$0") stats | jq .           # Get statistics in JSON

Part of: bd-1i44 - Add bead quality metrics tracking
EOF
}

#######################################
# Main function
#######################################
main() {
    if [ $# -lt 1 ]; then
        usage
        exit 1
    fi

    local command="$1"
    shift

    # Ensure quality reports file exists
    mkdir -p "$(dirname "$QUALITY_REPORTS")"
    touch "$QUALITY_REPORTS"

    case "$command" in
        score)
            if [ $# -lt 1 ]; then
                print_msg RED "Error: score requires a task_id"
                usage
                exit 1
            fi
            score_task "$1"
            ;;
        warn)
            if [ $# -lt 1 ]; then
                print_msg RED "Error: warn requires a task_id"
                usage
                exit 1
            fi
            warn_low_quality "$1"
            ;;
        report)
            show_report
            ;;
        stats)
            show_stats
            ;;
        --help|-h|help)
            usage
            exit 0
            ;;
        *)
            print_msg RED "Error: Unknown command '$command'"
            usage
            exit 1
            ;;
    esac
}

main "$@"
