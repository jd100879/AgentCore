#!/usr/bin/env bash
# assign-tasks.sh - Distribute Beads tasks to swarm agents
#
# Usage: ./scripts/assign-tasks.sh <swarm-session> [strategy] [options]
#
# Description:
#   Queries Beads for ready tasks and assigns them to available swarm agents
#   via agent mail. Supports multiple assignment strategies.
#
# Examples:
#   ./scripts/assign-tasks.sh phase3              # Round-robin (default)
#   ./scripts/assign-tasks.sh phase3 balanced     # Balanced by effort
#   ./scripts/assign-tasks.sh phase3 priority     # By priority
#   ./scripts/assign-tasks.sh phase3 --dry-run    # Preview assignments
#
# Part of: Component 2 - Agent Swarm Orchestration (bd-10t)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIDS_DIR="$PROJECT_ROOT/pids"

#######################################
# Print usage information
#######################################
usage() {
    cat <<EOF
Usage: $(basename "$0") <swarm-session> [strategy] [options]

Distribute Beads tasks to swarm agents via agent mail.

Arguments:
  swarm-session   Tmux session name from spawn-swarm.sh (required)
  strategy        Assignment strategy (default: round-robin)
                  - round-robin: Sequential distribution
                  - balanced: Minimize total work per agent
                  - priority: High-priority tasks first
                  - capability: Match agents to tasks by skills/workload/history

Options:
  --dry-run       Preview assignments without sending
  --help          Show this help message

Examples:
  $(basename "$0") phase3              # Round-robin assignment
  $(basename "$0") phase3 balanced     # Balanced by effort
  $(basename "$0") phase3 --dry-run    # Preview only

Strategies:
  round-robin - Distribute tasks sequentially (Agent1→T1, Agent2→T2, Agent1→T3...)
  balanced    - Minimize total estimated effort per agent
  priority    - Assign high-priority tasks first, respect dependencies
  capability  - Match tasks to agents based on skills, workload, and history (NTM)

Requirements:
  - Swarm must exist (created with spawn-swarm.sh)
  - Beads tasks must be available (status=open, no blockers)
  - Agent mail system must be running
EOF
}

#######################################
# Print colored message to stderr
# Arguments:
#   $1 - Color (RED, GREEN, YELLOW, BLUE)
#   $2 - Message
#######################################
print_msg() {
    local color="${!1}"
    local msg="$2"
    echo -e "${color}${msg}${NC}" >&2
}

#######################################
# Check if swarm state file exists
# Arguments:
#   $1 - Session name
#######################################
check_swarm_exists() {
    local session="$1"
    local state_file="$PIDS_DIR/swarm-${session}.state"

    if [ ! -f "$state_file" ]; then
        print_msg RED "Error: Swarm state file not found: $state_file"
        echo "" >&2
        echo "Swarm '$session' does not exist or was not created with spawn-swarm.sh" >&2
        echo "" >&2
        echo "Available swarms:" >&2
        ls "$PIDS_DIR"/swarm-*.state 2>/dev/null | sed 's/.*swarm-//;s/.state//' | sed 's/^/  - /' >&2 || echo "  (none found)" >&2
        exit 1
    fi
}

#######################################
# Read swarm state file
# Arguments:
#   $1 - Session name
# Returns: JSON state
#######################################
read_swarm_state() {
    local session="$1"
    local state_file="$PIDS_DIR/swarm-${session}.state"

    if ! cat "$state_file"; then
        print_msg RED "Error: Failed to read swarm state file"
        exit 1
    fi
}

#######################################
# Extract agent names from swarm state
# Arguments:
#   $1 - Swarm state JSON
# Returns: Space-separated agent names
#######################################
get_agent_names() {
    local state="$1"

    # Parse JSON manually to avoid jq dependency
    echo "$state" | grep '"name":' | sed 's/.*"name": "\([^"]*\)".*/\1/'
}

#######################################
# Verify agents are still active in tmux
# Arguments:
#   $1 - Session name
#   $2+ - Agent names
# Returns: Space-separated active agent names
#######################################
verify_active_agents() {
    local session="$1"
    shift
    local agents=("$@")
    local active_agents=()

    # Check if tmux session exists
    if ! tmux has-session -t "$session" 2>/dev/null; then
        print_msg YELLOW "Warning: Tmux session '$session' not found"
        print_msg YELLOW "Agents may not be active, but will still be considered available"
        # Return all agents anyway - they might be running elsewhere
        echo "${agents[@]}"
        return
    fi

    # All agents in the swarm are considered active if session exists
    active_agents=("${agents[@]}")

    echo "${active_agents[@]}"
}

#######################################
# Query Beads for ready tasks
# Returns: JSON array of tasks
#######################################
query_ready_tasks() {
    # Query Beads for open tasks
    local tasks_output=$(br list --status open 2>/dev/null || echo "")

    if [ -z "$tasks_output" ]; then
        echo "[]"
        return
    fi

    # Parse task list (br list output is human-readable, not JSON)
    # We'll need to parse it line by line
    # Format: "● bd-XXX · Title [● P# · STATUS]"

    local task_ids=()
    while IFS= read -r line; do
        if [[ "$line" =~ ○[[:space:]]+(bd-[a-z0-9]+) ]]; then
            task_ids+=("${BASH_REMATCH[1]}")
        fi
    done <<< "$tasks_output"

    # Return task IDs as JSON array
    if [ ${#task_ids[@]} -eq 0 ]; then
        echo "[]"
    else
        printf '%s\n' "${task_ids[@]}" | jq -R . | jq -s .
    fi
}

#######################################
# Get task details from Beads
# Arguments:
#   $1 - Task ID
# Returns: Task details (title, priority, effort estimate)
#######################################
get_task_details() {
    local task_id="$1"

    # Get task details from br show
    local task_info=$(br show "$task_id" 2>/dev/null || echo "")

    if [ -z "$task_info" ]; then
        echo "unknown|P3|unknown"
        return
    fi

    # Extract title (first line after ID line)
    local title=$(echo "$task_info" | head -1 | sed 's/^○ bd-[a-z0-9]* · \(.*\) \[●.*/\1/')

    # Extract priority (P1, P2, P3)
    local priority="P3"
    if echo "$task_info" | grep -q "● P1"; then
        priority="P1"
    elif echo "$task_info" | grep -q "● P2"; then
        priority="P2"
    fi

    # Extract effort estimate from description if available
    local effort="unknown"
    if echo "$task_info" | grep -qE "Estimated Effort.*[0-9]+-?[0-9]*"; then
        effort=$(echo "$task_info" | grep -oE "Estimated Effort.*[0-9]+-?[0-9]*" | grep -oE "[0-9]+-?[0-9]*" | head -1)
    elif echo "$task_info" | grep -qE "\*\*Estimated Effort:\*\*.*[0-9]+"; then
        effort=$(echo "$task_info" | grep -oE "\*\*Estimated Effort:\*\*.*[0-9]+" | grep -oE "[0-9]+" | head -1)
    fi

    echo "$title|$priority|$effort"
}

#######################################
# Assign tasks using round-robin strategy
# Arguments:
#   $1 - Space-separated agent names
#   $2 - JSON array of task IDs
# Returns: agent→task mapping (one per line: "agent|task")
#######################################
assign_round_robin() {
    local agents_str="$1"
    local tasks_json="$2"

    IFS=' ' read -ra agents <<< "$agents_str"
    local task_ids=($(echo "$tasks_json" | jq -r '.[]'))

    if [ ${#agents[@]} -eq 0 ]; then
        return
    fi

    if [ ${#task_ids[@]} -eq 0 ]; then
        return
    fi

    local agent_index=0
    for task_id in "${task_ids[@]}"; do
        local agent="${agents[$agent_index]}"
        echo "$agent|$task_id"

        # Round-robin: next agent
        agent_index=$(( (agent_index + 1) % ${#agents[@]} ))
    done
}

#######################################
# Assign tasks using balanced strategy
# Arguments:
#   $1 - Space-separated agent names
#   $2 - JSON array of task IDs
# Returns: agent→task mapping (one per line: "agent|task")
#######################################
assign_balanced() {
    local agents_str="$1"
    local tasks_json="$2"

    IFS=' ' read -ra agents <<< "$agents_str"
    local task_ids=($(echo "$tasks_json" | jq -r '.[]'))

    if [ ${#agents[@]} -eq 0 ]; then
        return
    fi

    if [ ${#task_ids[@]} -eq 0 ]; then
        return
    fi

    # Initialize agent workload tracking using indexed arrays
    local agent_loads=()
    for agent in "${agents[@]}"; do
        agent_loads+=(0)
    done

    # Assign each task to agent with least workload
    for task_id in "${task_ids[@]}"; do
        # Get task effort estimate
        local details=$(get_task_details "$task_id")
        local effort=$(echo "$details" | cut -d'|' -f3)

        # Parse effort (handle "4-6h" format)
        local effort_hours=4  # default
        if [[ "$effort" =~ ^([0-9]+) ]]; then
            effort_hours="${BASH_REMATCH[1]}"
        fi

        # Find agent with minimum workload
        local min_index=0
        local min_load=${agent_loads[0]}
        for ((i=1; i<${#agents[@]}; i++)); do
            if [ ${agent_loads[$i]} -lt $min_load ]; then
                min_load=${agent_loads[$i]}
                min_index=$i
            fi
        done

        local min_agent="${agents[$min_index]}"

        # Assign task to this agent
        echo "$min_agent|$task_id"

        # Update agent workload
        agent_loads[$min_index]=$((agent_loads[$min_index] + effort_hours))
    done
}

#######################################
# Assign tasks using priority strategy
# Arguments:
#   $1 - Space-separated agent names
#   $2 - JSON array of task IDs
# Returns: agent→task mapping (one per line: "agent|task")
#######################################
assign_priority() {
    local agents_str="$1"
    local tasks_json="$2"

    IFS=' ' read -ra agents <<< "$agents_str"
    local task_ids=($(echo "$tasks_json" | jq -r '.[]'))

    if [ ${#agents[@]} -eq 0 ]; then
        return
    fi

    if [ ${#task_ids[@]} -eq 0 ]; then
        return
    fi

    # Get priorities for all tasks and sort
    local task_with_priority=""
    for task_id in "${task_ids[@]}"; do
        local details=$(get_task_details "$task_id")
        local priority=$(echo "$details" | cut -d'|' -f2)
        task_with_priority="${task_with_priority}${priority}|${task_id}"$'\n'
    done

    # Sort by priority (P1 < P2 < P3 in ASCII, so this puts P1 first)
    local sorted_tasks=($(echo "$task_with_priority" | sort | cut -d'|' -f2))

    # Assign using round-robin on sorted tasks
    local agent_index=0
    for task_id in "${sorted_tasks[@]}"; do
        if [ -n "$task_id" ]; then
            local agent="${agents[$agent_index]}"
            echo "$agent|$task_id"

            agent_index=$(( (agent_index + 1) % ${#agents[@]} ))
        fi
    done
}

#######################################
# Assign tasks using capability strategy (NTM)
# Arguments:
#   $1 - Space-separated agent names
#   $2 - JSON array of task IDs
# Returns: agent→task mapping (one per line: "agent|task")
#######################################
assign_capability() {
    local agents_str="$1"
    local tasks_json="$2"

    IFS=' ' read -ra agents <<< "$agents_str"
    local task_ids=($(echo "$tasks_json" | jq -r '.[]'))

    if [ ${#agents[@]} -eq 0 ]; then
        return
    fi

    if [ ${#task_ids[@]} -eq 0 ]; then
        return
    fi

    # Check if match-engine.sh exists
    if [ ! -f "$PROJECT_ROOT/scripts/match-engine.sh" ]; then
        print_msg YELLOW "Warning: match-engine.sh not found, falling back to round-robin"
        assign_round_robin "$agents_str" "$tasks_json"
        return
    fi

    # For each task, find the best matching agent using match-engine
    for task_id in "${task_ids[@]}"; do
        # Convert agent array to comma-separated string
        local agents_csv=$(IFS=,; echo "${agents[*]}")

        # Get best match using match-engine.sh
        local best_agent=$("$PROJECT_ROOT/scripts/match-engine.sh" best-match "$task_id" "$agents_csv" 2>/dev/null || echo "")

        if [ -z "$best_agent" ]; then
            # Fallback to first available agent if scoring fails
            best_agent="${agents[0]}"
        fi

        echo "$best_agent|$task_id"
    done
}

#######################################
# Send task assignment via agent mail
# Arguments:
#   $1 - Agent name
#   $2 - Task ID
#   $3 - Task details (title|priority|effort)
#   $4 - Dry run flag (0=send, 1=preview)
#######################################
send_assignment() {
    local agent="$1"
    local task_id="$2"
    local details="$3"
    local dry_run="$4"

    IFS='|' read -r title priority effort <<< "$details"

    local subject="[$task_id] Task Assigned: $title"
    local body="You've been assigned $task_id.

Task: $title
Priority: $priority
Estimated: ${effort}h

To view: br show $task_id

—Swarm Coordinator"

    if [ "$dry_run" -eq 1 ]; then
        echo "$agent → $task_id ($title, ${effort}h)"
    else
        "$PROJECT_ROOT/scripts/agent-mail-helper.sh" send "$agent" "$task_id" "$subject" "$body" >/dev/null 2>&1
        print_msg GREEN "  ✓ Assigned $task_id to $agent"
    fi
}

#######################################
# Main function
#######################################
main() {
    local session=""
    local strategy="round-robin"
    local dry_run=0

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --help)
                usage
                exit 0
                ;;
            --dry-run)
                dry_run=1
                shift
                ;;
            *)
                if [ -z "$session" ]; then
                    session="$1"
                elif [[ "$1" =~ ^(round-robin|balanced|priority|capability)$ ]]; then
                    strategy="$1"
                else
                    print_msg RED "Error: Unknown argument '$1'"
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Validate required arguments
    if [ -z "$session" ]; then
        print_msg RED "Error: Swarm session name is required"
        usage
        exit 1
    fi

    # Check if swarm exists
    check_swarm_exists "$session"

    print_msg BLUE "========================================="
    print_msg BLUE "Task Assignment: $session"
    print_msg BLUE "========================================="
    echo "Strategy: $strategy" >&2
    echo "Dry run: $([ $dry_run -eq 1 ] && echo 'yes' || echo 'no')" >&2
    echo "" >&2

    # Read swarm state
    print_msg BLUE "Reading swarm state..." >&2
    local state=$(read_swarm_state "$session")

    # Get agent names
    local agents_str=$(get_agent_names "$state" | tr '\n' ' ')
    IFS=' ' read -ra agents <<< "$agents_str"

    if [ ${#agents[@]} -eq 0 ]; then
        print_msg RED "Error: No agents found in swarm"
        exit 1
    fi

    print_msg GREEN "Found ${#agents[@]} agents: ${agents[*]}" >&2

    # Verify agents are active
    local active_agents=$(verify_active_agents "$session" "${agents[@]}")

    # Query ready tasks
    print_msg BLUE "Querying Beads for ready tasks..." >&2
    local tasks_json=$(query_ready_tasks)
    local task_ids=($(echo "$tasks_json" | jq -r '.[]'))

    if [ ${#task_ids[@]} -eq 0 ]; then
        print_msg YELLOW "No ready tasks found in Beads"
        echo "" >&2
        echo "All tasks are either:" >&2
        echo "  - Already claimed" >&2
        echo "  - Blocked by dependencies" >&2
        echo "  - Not in 'open' status" >&2
        exit 0
    fi

    print_msg GREEN "Found ${#task_ids[@]} ready tasks" >&2
    echo "" >&2

    # Assign tasks using selected strategy
    print_msg BLUE "Assigning tasks using $strategy strategy..." >&2
    local assignments=""

    case "$strategy" in
        round-robin)
            assignments=$(assign_round_robin "$active_agents" "$tasks_json")
            ;;
        balanced)
            assignments=$(assign_balanced "$active_agents" "$tasks_json")
            ;;
        priority)
            assignments=$(assign_priority "$active_agents" "$tasks_json")
            ;;
        capability)
            assignments=$(assign_capability "$active_agents" "$tasks_json")
            ;;
    esac

    if [ -z "$assignments" ]; then
        print_msg YELLOW "No assignments generated"
        exit 0
    fi

    # Display and optionally send assignments
    local assignment_count=0

    if [ "$dry_run" -eq 1 ]; then
        print_msg YELLOW "DRY RUN - Preview of assignments:" >&2
        echo "" >&2
    fi

    while IFS='|' read -r agent task_id; do
        if [ -n "$agent" ] && [ -n "$task_id" ]; then
            local details=$(get_task_details "$task_id")
            send_assignment "$agent" "$task_id" "$details" "$dry_run"
            ((assignment_count++))
        fi
    done <<< "$assignments"

    echo "" >&2

    if [ "$dry_run" -eq 1 ]; then
        print_msg GREEN "$assignment_count assignments ready" >&2
        echo "Run without --dry-run to send assignments" >&2
    else
        print_msg GREEN "=========================================" >&2
        print_msg GREEN "$assignment_count assignments sent!" >&2
        print_msg GREEN "=========================================" >&2
        echo "Agents will receive task notifications via agent mail" >&2
    fi
}

# Run main function
main "$@"
