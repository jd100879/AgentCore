#!/usr/bin/env bash
# match-engine.sh - Agent-Task Compatibility Scoring (NTM)
#
# Usage:
#   ./scripts/match-engine.sh score <agent_name> <task_id>
#   ./scripts/match-engine.sh best-match <task_id> <agent1,agent2,...>
#
# Scoring Formula:
#   score = skill_match × workload_factor × history_score
#
#   - skill_match: Overlap between agent capabilities and task labels (0.0-1.0)
#   - workload_factor: Inverse of current workload (1.0 / (1 + num_tasks))
#   - history_score: Success rate with similar tasks (0.0-1.0, default 0.5)
#
# Part of: Phase 1 NTM Implementation (bd-1rm)

set -euo pipefail

# Project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TYPES_FILE="$PROJECT_ROOT/.agent-profiles/types.yaml"
INSTANCES_DIR="$PROJECT_ROOT/.agent-profiles/instances"
HISTORY_FILE="$PROJECT_ROOT/.beads/agent-history.jsonl"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#######################################
# Print colored message to stderr
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
  score <agent_name> <task_id>           Score agent-task compatibility (0.0-1.0)
  best-match <task_id> <agent1,agent2>   Find best agent for task from list

Scoring Algorithm:
  score = skill_match × workload_factor × history_score

  - skill_match: Overlap between agent capabilities and task labels (0.0-1.0)
  - workload_factor: Inverse of current workload (1.0 / (1 + num_tasks))
  - history_score: Success rate with similar tasks (0.0-1.0, default 0.5)

Examples:
  $(basename "$0") score HazyFinch bd-1rm
  $(basename "$0") best-match bd-1rm HazyFinch,RubyFox,DarkGlen

EOF
}

#######################################
# Get agent type from instance file
# Arguments:
#   $1 - Agent name
# Returns: Agent type or "general"
#######################################
get_agent_type() {
    local agent_name="$1"
    local instance_file="$INSTANCES_DIR/${agent_name}.json"

    if [ -f "$instance_file" ]; then
        jq -r '.type // "general"' "$instance_file" 2>/dev/null || echo "general"
    else
        echo "general"
    fi
}

#######################################
# Get agent capabilities
# Arguments:
#   $1 - Agent name
# Returns: Newline-separated list of capabilities
#######################################
get_agent_capabilities() {
    local agent_name="$1"
    local agent_type=$(get_agent_type "$agent_name")

    if ! command -v yq &> /dev/null; then
        # Fallback: return general capabilities
        echo "bash"
        echo "git"
        echo "documentation"
        return
    fi

    if [ ! -f "$TYPES_FILE" ]; then
        # Fallback: return general capabilities
        echo "bash"
        echo "git"
        return
    fi

    yq eval ".agent_types[] | select(.name == \"$agent_type\") | .capabilities[]" "$TYPES_FILE" 2>/dev/null || {
        echo "bash"
        echo "git"
    }
}

#######################################
# Get task labels
# Arguments:
#   $1 - Task ID
# Returns: Newline-separated list of labels
#######################################
get_task_labels() {
    local task_id="$1"

    # Get task details from br show
    local task_info=$(br show "$task_id" 2>/dev/null || echo "")

    if [ -z "$task_info" ]; then
        return
    fi

    # Extract labels line
    local labels_line=$(echo "$task_info" | grep "^Labels:" | sed 's/^Labels: //' || echo "")

    if [ -z "$labels_line" ]; then
        return
    fi

    # Split by comma and print each label
    echo "$labels_line" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

#######################################
# Calculate skill match score
# Arguments:
#   $1 - Agent name
#   $2 - Task ID
# Returns: Score between 0.0 and 1.0
#######################################
calc_skill_match() {
    local agent_name="$1"
    local task_id="$2"

    local capabilities=$(get_agent_capabilities "$agent_name")
    local labels=$(get_task_labels "$task_id")

    if [ -z "$labels" ]; then
        # No labels, moderate match (allow any agent)
        echo "0.6"
        return
    fi

    # Count matches
    local matches=0
    local total_labels=0

    while IFS= read -r label; do
        if [ -n "$label" ]; then
            ((total_labels++))
            # Check if any capability matches this label
            while IFS= read -r cap; do
                if [ -n "$cap" ] && [[ "$label" == *"$cap"* || "$cap" == *"$label"* ]]; then
                    ((matches++))
                    break
                fi
            done <<< "$capabilities"
        fi
    done <<< "$labels"

    if [ $total_labels -eq 0 ]; then
        echo "0.6"
        return
    fi

    # Calculate match ratio
    local score=$(echo "scale=2; $matches / $total_labels" | bc -l)

    # Ensure minimum score of 0.1 (agents can learn new skills)
    if (( $(echo "$score < 0.1" | bc -l) )); then
        echo "0.1"
    else
        echo "$score"
    fi
}

#######################################
# Get agent workload (number of active tasks)
# Arguments:
#   $1 - Agent name
# Returns: Number of active tasks
#######################################
get_agent_workload() {
    local agent_name="$1"

    # Query Beads for tasks owned by this agent with status in_progress
    local count=$(br list --status in_progress --format json 2>/dev/null | jq -r ".[] | select(.owner == \"$agent_name\") | .id" 2>/dev/null | wc -l | tr -d ' ')

    # Default to 0 if query fails
    if [ -z "$count" ]; then
        echo "0"
    else
        echo "$count"
    fi
}

#######################################
# Calculate workload factor
# Arguments:
#   $1 - Agent name
# Returns: Score between 0.0 and 1.0 (higher = less loaded)
#######################################
calc_workload_factor() {
    local agent_name="$1"
    local workload=$(get_agent_workload "$agent_name")

    # Formula: 1.0 / (1 + num_tasks)
    # 0 tasks = 1.0, 1 task = 0.5, 2 tasks = 0.33, 3 tasks = 0.25, etc.
    local factor=$(echo "scale=2; 1.0 / (1 + $workload)" | bc -l)

    echo "$factor"
}

#######################################
# Get agent history score for task type
# Arguments:
#   $1 - Agent name
#   $2 - Task ID
# Returns: Success rate 0.0-1.0 (default 0.5 if no history)
#######################################
calc_history_score() {
    local agent_name="$1"
    local task_id="$2"

    # Get task labels for similarity matching
    local labels=$(get_task_labels "$task_id")

    # Use performance-tracker.sh to calculate history score
    local tracker_script="$PROJECT_ROOT/scripts/performance-tracker.sh"

    if [ ! -f "$tracker_script" ]; then
        # Fallback: neutral score if tracker not available
        echo "0.5"
        return
    fi

    # Call performance tracker with agent and labels
    local score=$("$tracker_script" score "$agent_name" "$labels" 2>/dev/null || echo "0.5")

    echo "$score"
}

#######################################
# Calculate total compatibility score
# Arguments:
#   $1 - Agent name
#   $2 - Task ID
# Returns: Total score 0.0-1.0
#######################################
score_agent_task() {
    local agent_name="$1"
    local task_id="$2"

    local skill_match=$(calc_skill_match "$agent_name" "$task_id")
    local workload_factor=$(calc_workload_factor "$agent_name")
    local history_score=$(calc_history_score "$agent_name" "$task_id")

    # Total score = skill_match × workload_factor × history_score
    local total=$(echo "scale=3; $skill_match * $workload_factor * $history_score" | bc -l)

    echo "$total"
}

#######################################
# Score command - output detailed scoring
# Arguments:
#   $1 - Agent name
#   $2 - Task ID
#######################################
cmd_score() {
    local agent_name="$1"
    local task_id="$2"

    # Validate task exists
    if ! br show "$task_id" >/dev/null 2>&1; then
        print_msg RED "Error: Task '$task_id' not found"
        exit 1
    fi

    local skill_match=$(calc_skill_match "$agent_name" "$task_id")
    local workload_factor=$(calc_workload_factor "$agent_name")
    local history_score=$(calc_history_score "$agent_name" "$task_id")
    local total=$(score_agent_task "$agent_name" "$task_id")

    echo "Agent: $agent_name"
    echo "Task: $task_id"
    echo "---"
    echo "Skill Match:     $skill_match"
    echo "Workload Factor: $workload_factor"
    echo "History Score:   $history_score"
    echo "---"
    echo "Total Score:     $total"
}

#######################################
# Best-match command - find best agent for task
# Arguments:
#   $1 - Task ID
#   $2 - Comma-separated agent names
# Returns: Best agent name
#######################################
cmd_best_match() {
    local task_id="$1"
    local agents_csv="$2"

    # Validate task exists
    if ! br show "$task_id" >/dev/null 2>&1; then
        print_msg RED "Error: Task '$task_id' not found"
        exit 1
    fi

    IFS=',' read -ra agents <<< "$agents_csv"

    if [ ${#agents[@]} -eq 0 ]; then
        print_msg RED "Error: No agents provided"
        exit 1
    fi

    local best_agent=""
    local best_score=0.0

    for agent in "${agents[@]}"; do
        # Trim whitespace
        agent=$(echo "$agent" | xargs)

        if [ -z "$agent" ]; then
            continue
        fi

        local score=$(score_agent_task "$agent" "$task_id")

        # Compare scores (bc returns 1 if true, 0 if false)
        if (( $(echo "$score > $best_score" | bc -l) )); then
            best_score=$score
            best_agent=$agent
        fi
    done

    if [ -z "$best_agent" ]; then
        # Fallback to first agent
        best_agent="${agents[0]}"
    fi

    echo "$best_agent"
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
        score)
            if [ $# -lt 2 ]; then
                print_msg RED "Error: 'score' requires agent_name and task_id arguments"
                usage
                exit 1
            fi
            cmd_score "$1" "$2"
            ;;
        best-match)
            if [ $# -lt 2 ]; then
                print_msg RED "Error: 'best-match' requires task_id and agent_list arguments"
                usage
                exit 1
            fi
            cmd_best_match "$1" "$2"
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
