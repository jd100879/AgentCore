#!/usr/bin/env bash
# task-analyzer.sh - Extract task requirements from Beads for skill-based matching
#
# Usage:
#   ./scripts/task-analyzer.sh analyze <task-id>        # Analyze single task
#   ./scripts/task-analyzer.sh batch <task-ids...>      # Analyze multiple tasks
#   ./scripts/task-analyzer.sh profile <task-id>        # Get task profile JSON
#   ./scripts/task-analyzer.sh skills <task-id>         # List required skills only
#
# Part of: Phase 1 NTM Implementation (bd-2no)

set -euo pipefail

# Project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_REGISTRY="$PROJECT_ROOT/scripts/agent-registry.sh"

# Colors for output
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
  analyze <task-id>           Analyze task and show requirements
  batch <task-ids...>         Analyze multiple tasks
  profile <task-id>           Get task profile as JSON
  skills <task-id>            List required skills only
  complexity <task-id>        Estimate complexity (low/medium/high)
  queue [threshold]           Generate low-confidence task queue (default: 0.7)
  help                        Show this help message

Examples:
  $(basename "$0") analyze bd-1f5
  $(basename "$0") batch bd-1f5 bd-2no bd-1rm
  $(basename "$0") profile bd-2no
  $(basename "$0") skills bd-10w
  $(basename "$0") queue 0.7

Output:
  Task profiles include:
  - required_skills: List of skills/technologies needed
  - complexity: Estimated complexity (low/medium/high)
  - confidence: Extraction confidence (0.0-1.0)
  - extraction_method: How skills were extracted
  - priority: Task priority from Beads
  - description_hints: Skills extracted from description
  - label_hints: Skills extracted from labels

EOF
}

#######################################
# Extract skills from labels
# Arguments:
#   $1 - JSON array of labels
# Returns: Space-separated skill list
#######################################
extract_label_skills() {
    local labels_json="$1"

    # Known skill labels that map to agent capabilities
    local skill_mapping='
bash|bash
python|python
javascript|javascript
typescript|typescript
nodejs|nodejs
react|react
vue|vue
api|api
database|database
docker|docker
kubernetes|kubernetes
ci-cd|ci-cd
testing|testing
documentation|documentation
markdown|markdown
refactoring|refactoring
debugging|debugging
performance|performance
security|security
automation|automation
integration|integration
monitoring|monitoring
yaml|yaml
json|json
'

    local skills=""

    # Parse labels and match against skill mapping
    while IFS='|' read -r label skill; do
        if echo "$labels_json" | jq -e --arg label "$label" 'index($label) != null' >/dev/null 2>&1; then
            skills="$skills $skill"
        fi
    done <<< "$skill_mapping"

    echo "$skills" | xargs
}

#######################################
# Extract skills from description text
# Arguments:
#   $1 - Description text
# Returns: Space-separated skill list
#######################################
extract_description_skills() {
    local description="$1"
    local skills=""

    # Common technology keywords in descriptions
    local tech_keywords=(
        "python" "bash" "shell" "javascript" "typescript" "nodejs" "node.js"
        "react" "vue" "angular" "html" "css"
        "api" "rest" "graphql" "database" "sql" "postgres" "mysql" "redis"
        "docker" "kubernetes" "k8s" "ci" "cd" "jenkins" "github-actions"
        "testing" "tests" "unit-test" "integration-test" "e2e"
        "documentation" "docs" "markdown" "readme"
        "refactor" "debug" "optimize" "performance"
        "yaml" "json" "xml"
    )

    # Convert description to lowercase for matching
    local desc_lower=$(echo "$description" | tr '[:upper:]' '[:lower:]')

    # Check for each keyword
    for keyword in "${tech_keywords[@]}"; do
        if echo "$desc_lower" | grep -q "\b$keyword\b"; then
            # Normalize keyword
            case "$keyword" in
                "node.js") skills="$skills nodejs" ;;
                "shell") skills="$skills bash" ;;
                "k8s") skills="$skills kubernetes" ;;
                "github-actions") skills="$skills ci-cd" ;;
                "postgres"|"mysql"|"sql"|"redis") skills="$skills database" ;;
                "unit-test"|"integration-test"|"e2e"|"tests") skills="$skills testing" ;;
                "docs"|"readme") skills="$skills documentation" ;;
                "refactor") skills="$skills refactoring" ;;
                "debug") skills="$skills debugging" ;;
                "optimize") skills="$skills performance" ;;
                *) skills="$skills $keyword" ;;
            esac
        fi
    done

    echo "$skills" | xargs
}

#######################################
# Calculate confidence score based on extraction method
# Arguments:
#   $1 - Label skills (space-separated)
#   $2 - Description skills (space-separated)
# Returns: Confidence score (0.0-1.0) and extraction method
# Output format: "confidence|method|sources"
#######################################
calculate_confidence() {
    local label_skills="$1"
    local desc_skills="$2"

    local confidence="0.5"
    local method="description_parse"
    local sources="description"

    # Priority 1: Explicit label matches (highest confidence)
    if [ -n "$label_skills" ]; then
        confidence="0.9"
        method="label_match"
        if [ -n "$desc_skills" ]; then
            sources="labels+description"
        else
            sources="labels"
        fi
    # Priority 2: Strong keyword matches in description
    elif [ -n "$desc_skills" ]; then
        # Count how many distinct skills found
        local skill_count=$(echo "$desc_skills" | wc -w)

        if [ "$skill_count" -ge 3 ]; then
            # Multiple strong keywords = higher confidence
            confidence="0.7"
            method="keyword_heuristic"
        else
            # Few keywords = moderate confidence
            confidence="0.5"
            method="description_parse"
        fi
        sources="description"
    # Priority 3: No skills detected (general task)
    else
        confidence="0.3"
        method="no_match"
        sources="none"
    fi

    echo "${confidence}|${method}|${sources}"
}

#######################################
# Estimate task complexity
# Arguments:
#   $1 - Description text
#   $2 - Priority (1-3)
# Returns: low|medium|high
#######################################
estimate_complexity() {
    local description="$1"
    local priority="${2:-2}"

    # Count indicators of complexity
    local complexity_score=0

    # Check description length
    local desc_length=${#description}
    if [ $desc_length -gt 1000 ]; then
        ((complexity_score += 2))
    elif [ $desc_length -gt 500 ]; then
        ((complexity_score += 1))
    fi

    # Check for complex keywords
    local complex_keywords=(
        "architecture" "refactor" "migration" "integration"
        "multi" "distributed" "scalable" "performance"
        "security" "optimization"
    )

    for keyword in "${complex_keywords[@]}"; do
        if echo "$description" | grep -qi "\b$keyword"; then
            ((complexity_score += 1))
        fi
    done

    # Check for multiple file modifications
    if echo "$description" | grep -c "EDIT:\|NEW:\|DELETE:" | grep -q "[3-9]"; then
        ((complexity_score += 1))
    fi

    # Priority factor (P1 = high stakes)
    if [ "$priority" -eq 1 ]; then
        ((complexity_score += 1))
    fi

    # Determine complexity level
    if [ $complexity_score -ge 4 ]; then
        echo "high"
    elif [ $complexity_score -ge 2 ]; then
        echo "medium"
    else
        echo "low"
    fi
}

#######################################
# Analyze a single task
# Arguments:
#   $1 - Task ID
# Returns: Human-readable analysis
#######################################
analyze_task() {
    local task_id="$1"

    # Fetch task data
    local task_json=$(br show "$task_id" --format json 2>/dev/null)

    if [ -z "$task_json" ] || [ "$task_json" = "[]" ]; then
        print_msg RED "Error: Task '$task_id' not found"
        return 1
    fi

    # Extract fields
    local title=$(echo "$task_json" | jq -r '.[0].title')
    local description=$(echo "$task_json" | jq -r '.[0].description')
    local labels=$(echo "$task_json" | jq -c '.[0].labels // []')
    local priority=$(echo "$task_json" | jq -r '.[0].priority // 2')

    # Extract skills
    local label_skills=$(extract_label_skills "$labels")
    local desc_skills=$(extract_description_skills "$description")

    # Combine and deduplicate skills
    local all_skills=$(echo "$label_skills $desc_skills" | tr ' ' '\n' | sort -u | tr '\n' ' ' | xargs)

    # Estimate complexity
    local complexity=$(estimate_complexity "$description" "$priority")

    # Calculate confidence
    local confidence_result=$(calculate_confidence "$label_skills" "$desc_skills")
    local confidence=$(echo "$confidence_result" | cut -d'|' -f1)
    local extraction_method=$(echo "$confidence_result" | cut -d'|' -f2)
    local skill_sources=$(echo "$confidence_result" | cut -d'|' -f3)

    # Output analysis
    echo "Task Analysis: $task_id"
    echo "======================"
    echo "Title: $title"
    echo "Priority: P$priority"
    echo "Complexity: $complexity"
    echo "Confidence: $confidence ($extraction_method)"
    echo ""
    echo "Required Skills:"
    if [ -n "$all_skills" ]; then
        for skill in $all_skills; do
            echo "  - $skill"
        done
    else
        echo "  - general (no specific skills detected)"
    fi
    echo ""
    echo "Skill Sources:"
    echo "  Labels: ${label_skills:-none}"
    echo "  Description: ${desc_skills:-none}"
    echo "  Sources: $skill_sources"
}

#######################################
# Get task profile as JSON
# Arguments:
#   $1 - Task ID
# Returns: JSON task profile
#######################################
get_task_profile() {
    local task_id="$1"

    # Fetch task data
    local task_json=$(br show "$task_id" --format json 2>/dev/null)

    if [ -z "$task_json" ] || [ "$task_json" = "[]" ]; then
        echo "{\"error\": \"Task not found\"}"
        return 1
    fi

    # Extract fields
    local title=$(echo "$task_json" | jq -r '.[0].title')
    local description=$(echo "$task_json" | jq -r '.[0].description')
    local labels=$(echo "$task_json" | jq -c '.[0].labels // []')
    local priority=$(echo "$task_json" | jq -r '.[0].priority // 2')

    # Extract skills
    local label_skills=$(extract_label_skills "$labels")
    local desc_skills=$(extract_description_skills "$description")

    # Combine and deduplicate skills
    local all_skills=$(echo "$label_skills $desc_skills" | tr ' ' '\n' | sort -u | tr '\n' ' ' | xargs)

    # Estimate complexity
    local complexity=$(estimate_complexity "$description" "$priority")

    # Calculate confidence score
    local confidence_result=$(calculate_confidence "$label_skills" "$desc_skills")
    local confidence=$(echo "$confidence_result" | cut -d'|' -f1)
    local extraction_method=$(echo "$confidence_result" | cut -d'|' -f2)
    local skill_sources=$(echo "$confidence_result" | cut -d'|' -f3)

    # Build JSON profile manually (avoid jq complexity)
    local skills_json="["
    local first=true
    for skill in $all_skills; do
        if [ "$first" = true ]; then
            skills_json="${skills_json}\"$skill\""
            first=false
        else
            skills_json="${skills_json}, \"$skill\""
        fi
    done
    skills_json="${skills_json}]"

    # If no skills found, use "general"
    if [ "$all_skills" = "" ]; then
        skills_json='["general"]'
    fi

    cat <<EOF
{
  "task_id": "$task_id",
  "title": "$title",
  "priority": $priority,
  "complexity": "$complexity",
  "confidence": $confidence,
  "extraction_method": "$extraction_method",
  "skill_sources": "$skill_sources",
  "required_skills": $skills_json,
  "label_skills": $(echo "$label_skills" | jq -R 'split(" ") | map(select(length > 0))'),
  "description_skills": $(echo "$desc_skills" | jq -R 'split(" ") | map(select(length > 0))')
}
EOF
}

#######################################
# List required skills only
# Arguments:
#   $1 - Task ID
# Returns: Space-separated skill list
#######################################
list_skills() {
    local task_id="$1"

    # Fetch task data
    local task_json=$(br show "$task_id" --format json 2>/dev/null)

    if [ -z "$task_json" ] || [ "$task_json" = "[]" ]; then
        return 1
    fi

    # Extract fields
    local description=$(echo "$task_json" | jq -r '.[0].description')
    local labels=$(echo "$task_json" | jq -c '.[0].labels // []')

    # Extract skills
    local label_skills=$(extract_label_skills "$labels")
    local desc_skills=$(extract_description_skills "$description")

    # Combine and deduplicate skills
    local all_skills=$(echo "$label_skills $desc_skills" | tr ' ' '\n' | sort -u | tr '\n' ' ' | xargs)

    if [ -z "$all_skills" ]; then
        echo "general"
    else
        echo "$all_skills"
    fi
}

#######################################
# Get complexity only
# Arguments:
#   $1 - Task ID
# Returns: low|medium|high
#######################################
get_complexity() {
    local task_id="$1"

    # Fetch task data
    local task_json=$(br show "$task_id" --format json 2>/dev/null)

    if [ -z "$task_json" ] || [ "$task_json" = "[]" ]; then
        echo "unknown"
        return 1
    fi

    # Extract fields
    local description=$(echo "$task_json" | jq -r '.[0].description')
    local priority=$(echo "$task_json" | jq -r '.[0].priority // 2')

    # Estimate complexity
    estimate_complexity "$description" "$priority"
}

#######################################
# Batch analyze multiple tasks
# Arguments:
#   $@ - Task IDs
#######################################
batch_analyze() {
    local task_ids=("$@")

    echo "Batch Task Analysis"
    echo "==================="
    echo ""

    for task_id in "${task_ids[@]}"; do
        analyze_task "$task_id"
        echo ""
        echo "---"
        echo ""
    done
}

#######################################
# Generate low-confidence task queue
# Scans all open tasks and identifies those with confidence <0.7
# Writes results to .beads/low-confidence-tasks.json
#######################################
generate_low_confidence_queue() {
    local threshold="${1:-0.7}"
    local output_file="$PROJECT_ROOT/.beads/low-confidence-tasks.json"

    print_msg BLUE "Scanning open tasks for low-confidence matches (threshold: $threshold)..."

    # Get all open task IDs
    local task_ids=$(br list --status open 2>/dev/null | grep -oE 'bd-[a-z0-9]+' | sort -u)

    if [ -z "$task_ids" ]; then
        print_msg YELLOW "No open tasks found"
        echo '{"tasks": [], "generated_at": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'", "threshold": '$threshold'}' > "$output_file"
        return
    fi

    # Analyze each task and collect low-confidence ones
    local low_conf_tasks="[]"
    local count=0

    for task_id in $task_ids; do
        local profile=$(get_task_profile "$task_id" 2>/dev/null)

        if [ $? -eq 0 ] && [ -n "$profile" ]; then
            local confidence=$(echo "$profile" | jq -r '.confidence // 0.5')

            # Compare confidence with threshold
            local is_low=$(echo "$confidence < $threshold" | bc -l 2>/dev/null || echo "0")

            if [ "$is_low" = "1" ]; then
                # Add to low-confidence list
                low_conf_tasks=$(echo "$low_conf_tasks" | jq --argjson task "$profile" '. += [$task]')
                ((count++))
                print_msg YELLOW "  ✗ $task_id: confidence=$confidence"
            else
                print_msg GREEN "  ✓ $task_id: confidence=$confidence"
            fi
        fi
    done

    # Write to output file
    local queue_json=$(jq -n \
        --argjson tasks "$low_conf_tasks" \
        --arg generated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --argjson threshold "$threshold" \
        --argjson count "$count" \
        '{
            tasks: $tasks,
            generated_at: $generated_at,
            threshold: $threshold,
            count: $count,
            description: "Tasks requiring manual skill review due to low extraction confidence"
        }')

    echo "$queue_json" > "$output_file"

    print_msg GREEN "\n✓ Low-confidence queue generated: $output_file"
    print_msg BLUE "  Found $count tasks below threshold $threshold"
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
        analyze)
            if [ $# -lt 1 ]; then
                print_msg RED "Error: 'analyze' requires task ID argument"
                usage
                exit 1
            fi
            analyze_task "$1"
            ;;
        batch)
            if [ $# -lt 1 ]; then
                print_msg RED "Error: 'batch' requires at least one task ID"
                usage
                exit 1
            fi
            batch_analyze "$@"
            ;;
        profile)
            if [ $# -lt 1 ]; then
                print_msg RED "Error: 'profile' requires task ID argument"
                usage
                exit 1
            fi
            get_task_profile "$1"
            ;;
        skills)
            if [ $# -lt 1 ]; then
                print_msg RED "Error: 'skills' requires task ID argument"
                usage
                exit 1
            fi
            list_skills "$1"
            ;;
        complexity)
            if [ $# -lt 1 ]; then
                print_msg RED "Error: 'complexity' requires task ID argument"
                usage
                exit 1
            fi
            get_complexity "$1"
            ;;
        queue)
            local threshold="${1:-0.7}"
            generate_low_confidence_queue "$threshold"
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
