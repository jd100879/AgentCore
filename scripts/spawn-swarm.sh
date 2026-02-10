#!/usr/bin/env bash
# spawn-swarm.sh - Launch N coordinated agents in tmux panes
#
# Usage: ./scripts/spawn-swarm.sh <count> [session-name]
#
# Description:
#   Spawns N agents in tmux panes, each running Claude Code with unique identities.
#   Creates swarm state file for tracking and coordination.
#
# Examples:
#   ./scripts/spawn-swarm.sh 3              # Spawn 3 agents in "swarm-1"
#   ./scripts/spawn-swarm.sh 5 phase3      # Spawn 5 agents in "phase3"
#   ./scripts/spawn-swarm.sh 4 --agents DarkGlen,HazyFinch,WindyOwl,RubyFox
#
# Part of: Component 2 - Agent Swarm Orchestration (bd-1au)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default agent name pool
DEFAULT_AGENTS=(
    "DarkGlen"
    "HazyFinch"
    "WindyOwl"
    "RubyFox"
    "SwiftBadger"
    "BrightCrane"
    "SilentOtter"
    "StormyRaven"
    "QuickPanda"
    "GoldenEagle"
)

# Project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIDS_DIR="$PROJECT_ROOT/pids"

# Ensure pids directory exists
mkdir -p "$PIDS_DIR"

#######################################
# Print usage information
#######################################
usage() {
    cat <<EOF
Usage: $(basename "$0") <count> [session-name] [options]

Launch N coordinated agents in tmux panes, each running Claude Code.

Arguments:
  count           Number of agents to spawn (required)
  session-name    Tmux session name (default: swarm-1, swarm-2, etc.)

Options:
  --agents NAME1,NAME2,...  Custom agent names (comma-separated)
  --type TYPE               Agent type (default: general)
  --product UID             Link swarm to product (enables cross-repo work)
  --help                    Show this help message

Examples:
  $(basename "$0") 3                      # Spawn 3 agents in "swarm-1"
  $(basename "$0") 5 phase3               # Spawn 5 agents in "phase3"
  $(basename "$0") 4 --agents DarkGlen,HazyFinch,WindyOwl,RubyFox
  $(basename "$0") 3 --type backend       # Spawn 3 backend agents
  $(basename "$0") 2 dev --type frontend  # Spawn 2 frontend agents in "dev"
  $(basename "$0") 3 --product my-product-uid  # Spawn product-aware swarm

Agent Naming:
  Default pool: DarkGlen, HazyFinch, WindyOwl, RubyFox, SwiftBadger, ...
  Custom names: Use --agents flag with comma-separated list

Agent Types:
  Default: general (general-purpose agents)
  Available types: Use './scripts/agent-registry.sh list' to see all types
  Custom type: Use --type flag

Layouts:
  N ≤ 4:  2x2 grid (vertical split)
  N > 4:  Tiled layout (automatic)

Output:
  Creates swarm state file: ./pids/swarm-{session}.state
  Creates agent name files: ./pids/swarm-{session}.agent-N.name
EOF
}

#######################################
# Print colored message
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
# Check if tmux is available
#######################################
check_tmux() {
    if ! command -v tmux &> /dev/null; then
        print_msg RED "Error: tmux is not installed"
        echo "Please install tmux first:"
        echo "  macOS: brew install tmux"
        echo "  Linux: apt-get install tmux or yum install tmux"
        exit 1
    fi
}

#######################################
# Generate default session name
# Returns: Next available swarm-N name
#######################################
generate_session_name() {
    local n=1
    while tmux has-session -t "swarm-$n" 2>/dev/null; do
        ((n++))
    done
    echo "swarm-$n"
}

#######################################
# Check if session already exists
# Arguments:
#   $1 - Session name
#######################################
check_session_exists() {
    local session="$1"

    if tmux has-session -t "$session" 2>/dev/null; then
        print_msg RED "Error: Tmux session '$session' already exists"
        echo ""
        echo "Options:"
        echo "  1. Use a different session name"
        echo "  2. Kill existing session: tmux kill-session -t $session"
        echo "  3. Attach to existing session: tmux attach -t $session"
        exit 1
    fi
}

#######################################
# Validate agent count
# Arguments:
#   $1 - Agent count
#######################################
validate_agent_count() {
    local count="$1"

    if ! [[ "$count" =~ ^[0-9]+$ ]]; then
        print_msg RED "Error: Agent count must be a positive integer"
        exit 1
    fi

    if [ "$count" -lt 1 ]; then
        print_msg RED "Error: Agent count must be at least 1"
        exit 1
    fi

    if [ "$count" -gt 10 ]; then
        print_msg YELLOW "Warning: Spawning $count agents may consume significant resources"
        echo "Press Ctrl+C to cancel, or wait 5 seconds to continue..."
        sleep 5
    fi
}

#######################################
# Parse custom agent names from --agents flag
# Arguments:
#   $1 - Comma-separated agent names
# Returns: Array of agent names
#######################################
parse_custom_agents() {
    local agents_str="$1"
    IFS=',' read -ra CUSTOM_AGENTS <<< "$agents_str"
    echo "${CUSTOM_AGENTS[@]}"
}

#######################################
# Get agent names for the swarm
# Arguments:
#   $1 - Agent count
#   $2 - Custom agents (optional, space-separated)
# Returns: Array of agent names
#######################################
get_agent_names() {
    local count="$1"
    shift
    local custom_agents=("$@")
    local agents=()

    if [ ${#custom_agents[@]} -gt 0 ]; then
        # Use custom agents
        if [ ${#custom_agents[@]} -lt "$count" ]; then
            print_msg RED "Error: Not enough custom agent names (need $count, got ${#custom_agents[@]})"
            exit 1
        fi
        agents=("${custom_agents[@]:0:$count}")
    else
        # Use default agent pool
        if [ "$count" -gt ${#DEFAULT_AGENTS[@]} ]; then
            print_msg YELLOW "Warning: Need $count agents but only ${#DEFAULT_AGENTS[@]} in default pool"
            print_msg YELLOW "Generating additional agent names..."

            # Use default pool + generated names
            agents=("${DEFAULT_AGENTS[@]}")
            for ((i=${#DEFAULT_AGENTS[@]}; i<count; i++)); do
                agents+=("Agent-$((i+1))")
            done
        else
            agents=("${DEFAULT_AGENTS[@]:0:$count}")
        fi
    fi

    echo "${agents[@]}"
}

#######################################
# Create tmux session with N panes
# Arguments:
#   $1 - Session name
#   $2 - Agent count
#   $3+ - Agent names
#######################################
create_tmux_session() {
    local session="$1"
    local count="$2"
    shift 2
    local agents=("$@")

    print_msg BLUE "Creating tmux session '$session' with $count panes..."

    # Create initial session with first pane
    tmux new-session -d -s "$session" -n "swarm"

    # Create additional panes
    for ((i=1; i<count; i++)); do
        if [ "$count" -le 4 ]; then
            # Use vertical/horizontal split for 2-4 agents
            if [ $((i % 2)) -eq 1 ]; then
                tmux split-window -t "$session" -h
            else
                tmux split-window -t "$session" -v
            fi
        else
            # Use tiled layout for 5+ agents
            tmux split-window -t "$session"
        fi

        # Balance the layout after each split
        tmux select-layout -t "$session" tiled
    done

    # Final layout adjustment
    if [ "$count" -le 4 ]; then
        tmux select-layout -t "$session" tiled
    fi

    print_msg GREEN "✓ Created $count tmux panes"
}

#######################################
# Initialize agents in each pane
# Arguments:
#   $1 - Session name
#   $2 - Agent count
#   $3+ - Agent names
# Returns: Array of pane IDs
#######################################
initialize_agents() {
    local session="$1"
    local count="$2"
    shift 2
    local agents=("$@")
    local pane_ids=()

    print_msg BLUE "Initializing agents in panes..."

    for ((i=0; i<count; i++)); do
        local agent_name="${agents[$i]}"
        local pane_index=$i

        # Get pane ID
        local pane_id=$(tmux list-panes -t "$session" -F "#{pane_id}" | sed -n "$((i+1))p")
        pane_ids+=("$pane_id")

        # Write agent name file
        echo "$agent_name" > "$PIDS_DIR/swarm-${session}.agent-${pane_index}.name"

        # Send commands to pane to start Claude Code with agent identity
        tmux send-keys -t "$pane_id" "cd '$PROJECT_ROOT'" C-m
        tmux send-keys -t "$pane_id" "export CLAUDE_AGENT_NAME='$agent_name'" C-m
        tmux send-keys -t "$pane_id" "# Agent: $agent_name (Pane $pane_index)" C-m

        # Note: Not auto-starting Claude Code to allow agents to set up manually
        # This gives more control and avoids potential issues with auto-start

        print_msg GREEN "  ✓ Initialized $agent_name in pane $pane_index ($pane_id)"
    done

    echo "${pane_ids[@]}"
}

#######################################
# Create swarm state file
# Arguments:
#   $1 - Session name
#   $2 - Agent count
#   $3 - Space-separated agent names
#   $4 - Space-separated pane IDs
#   $5 - Agent type (optional, default: general)
#   $6 - Product UID (optional, for cross-repo work)
#######################################
create_state_file() {
    local session="$1"
    local count="$2"
    local agents_str="$3"
    local pane_ids_str="$4"
    local agent_type="${5:-general}"
    local product_uid="${6:-}"

    IFS=' ' read -ra agents <<< "$agents_str"
    IFS=' ' read -ra pane_ids <<< "$pane_ids_str"

    local state_file="$PIDS_DIR/swarm-${session}.state"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Build JSON manually to avoid jq dependency
    # Include product_uid if set (enables cross-repo work)
    local product_field=""
    if [ -n "$product_uid" ]; then
        product_field=",\n  \"product_uid\": \"$product_uid\""
    fi

    cat > "$state_file" <<EOF
{
  "session": "$session",
  "count": $count,
  "agent_type": "$agent_type",
  "spawn_time": "$timestamp",
  "project_root": "$PROJECT_ROOT"${product_field},
  "agents": [
EOF

    # Add agent entries
    for ((i=0; i<count; i++)); do
        local agent_name="${agents[$i]}"
        local pane_id="${pane_ids[$i]}"
        local comma=""
        [ $i -lt $((count-1)) ] && comma=","

        cat >> "$state_file" <<EOF
    {
      "index": $i,
      "name": "$agent_name",
      "pane_id": "$pane_id",
      "name_file": "./pids/swarm-${session}.agent-${i}.name"
    }${comma}
EOF
    done

    cat >> "$state_file" <<EOF
  ]
}
EOF

    print_msg GREEN "✓ Created state file: $state_file"
}

#######################################
# Verify swarm initialization
# Arguments:
#   $1 - Session name
#   $2 - Agent count
#######################################
verify_swarm() {
    local session="$1"
    local count="$2"

    print_msg BLUE "Verifying swarm initialization..."

    # Check tmux session
    if ! tmux has-session -t "$session" 2>/dev/null; then
        print_msg RED "✗ Tmux session '$session' not found"
        return 1
    fi

    # Check pane count
    local actual_panes=$(tmux list-panes -t "$session" | wc -l | tr -d ' ')
    if [ "$actual_panes" -ne "$count" ]; then
        print_msg RED "✗ Expected $count panes, found $actual_panes"
        return 1
    fi

    # Check agent name files
    local missing_files=0
    for ((i=0; i<count; i++)); do
        if [ ! -f "$PIDS_DIR/swarm-${session}.agent-${i}.name" ]; then
            print_msg RED "✗ Missing agent name file: agent-${i}.name"
            ((missing_files++))
        fi
    done

    if [ $missing_files -gt 0 ]; then
        return 1
    fi

    # Check state file
    if [ ! -f "$PIDS_DIR/swarm-${session}.state" ]; then
        print_msg RED "✗ Missing state file"
        return 1
    fi

    print_msg GREEN "✓ Swarm verification passed"
    return 0
}

#######################################
# Main function
#######################################
main() {
    local agent_count=""
    local session_name=""
    local custom_agents=()
    local agent_type="general"  # Default type
    local product_uid=""  # Product-scoped swarm

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --help)
                usage
                exit 0
                ;;
            --agents)
                shift
                IFS=' ' read -ra custom_agents <<< "$(parse_custom_agents "$1")"
                shift
                ;;
            --type)
                shift
                agent_type="$1"
                shift
                ;;
            --product)
                shift
                product_uid="$1"
                shift
                ;;
            *)
                if [ -z "$agent_count" ]; then
                    agent_count="$1"
                elif [ -z "$session_name" ]; then
                    session_name="$1"
                else
                    print_msg RED "Error: Unexpected argument '$1'"
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Validate required arguments
    if [ -z "$agent_count" ]; then
        print_msg RED "Error: Agent count is required"
        usage
        exit 1
    fi

    # Validate agent count
    validate_agent_count "$agent_count"

    # Generate session name if not provided
    if [ -z "$session_name" ]; then
        session_name=$(generate_session_name)
    fi

    # Check dependencies
    check_tmux

    # Check if session already exists
    check_session_exists "$session_name"

    # Validate agent type
    if [ -f "$PROJECT_ROOT/scripts/agent-registry.sh" ]; then
        if ! "$PROJECT_ROOT/scripts/agent-registry.sh" validate "$agent_type" >/dev/null 2>&1; then
            print_msg RED "Error: Invalid agent type '$agent_type'"
            echo ""
            echo "Available types:"
            "$PROJECT_ROOT/scripts/agent-registry.sh" list
            exit 1
        fi
    fi

    # Get agent names
    local agents
    if [ ${#custom_agents[@]} -gt 0 ]; then
        IFS=' ' read -ra agents <<< "$(get_agent_names "$agent_count" "${custom_agents[@]}")"
    else
        IFS=' ' read -ra agents <<< "$(get_agent_names "$agent_count")"
    fi

    # Record start time
    local start_time=$(date +%s)

    print_msg BLUE "========================================="
    print_msg BLUE "Spawning Swarm: $session_name"
    print_msg BLUE "========================================="
    echo "Agent count: $agent_count"
    echo "Session name: $session_name"
    echo "Agent type: $agent_type"
    echo "Agent names: ${agents[*]}"
    echo ""

    # Create tmux session with panes
    create_tmux_session "$session_name" "$agent_count" "${agents[@]}"

    # Initialize agents
    local pane_ids
    IFS=' ' read -ra pane_ids <<< "$(initialize_agents "$session_name" "$agent_count" "${agents[@]}")"

    # Register agents in the registry
    if [ -f "$PROJECT_ROOT/scripts/agent-registry.sh" ]; then
        print_msg BLUE "Registering agents in registry..."
        for agent_name in "${agents[@]}"; do
            "$PROJECT_ROOT/scripts/agent-registry.sh" register "$agent_name" "$agent_type" 2>/dev/null || true
        done
        print_msg GREEN "✓ Agents registered as type '$agent_type'"
    fi

    # Create state file
    create_state_file "$session_name" "$agent_count" "${agents[*]}" "${pane_ids[*]}" "$agent_type" "$product_uid"

    # Verify initialization
    if ! verify_swarm "$session_name" "$agent_count"; then
        print_msg RED "Swarm verification failed!"
        exit 1
    fi

    # Calculate spawn time
    local end_time=$(date +%s)
    local spawn_time=$((end_time - start_time))

    print_msg GREEN "========================================="
    print_msg GREEN "Swarm spawned successfully!"
    print_msg GREEN "========================================="
    echo "Session: $session_name"
    echo "Agents: $agent_count"
    echo "Spawn time: ${spawn_time}s"
    echo ""

    # Open in iTerm2 if available (check LC_TERMINAL for tmux compatibility)
    if [ "${LC_TERMINAL:-}" = "iTerm2" ] || [ "${TERM_PROGRAM:-}" = "iTerm.app" ]; then
        echo "Opening session in new iTerm tab..."
        osascript <<EOF
tell application "iTerm"
    tell current window
        create tab with default profile command "tmux attach -t $session_name"
    end tell
end tell
EOF
        print_msg GREEN "✓ Session opened in new tab"
    else
        echo "Next steps:"
        echo "  1. Attach to session: tmux attach -t $session_name"
        echo "  2. Navigate panes: Ctrl+b then arrow keys"
        echo "  3. Start Claude Code in each pane: claude"
    fi

    echo ""
    echo "State file: $PIDS_DIR/swarm-${session_name}.state"

    # Check performance target
    if [ $spawn_time -lt 30 ]; then
        print_msg GREEN "✓ Performance target met: ${spawn_time}s < 30s"
    else
        print_msg YELLOW "⚠ Performance target missed: ${spawn_time}s ≥ 30s"
    fi
}

# Run main function
main "$@"
