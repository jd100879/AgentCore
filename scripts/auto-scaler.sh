#!/usr/bin/env bash
# auto-scaler.sh - Dynamic agent spawning and teardown based on queue composition
#
# Usage:
#   ./scripts/auto-scaler.sh analyze                    # Analyze queue and recommend scaling
#   ./scripts/auto-scaler.sh scale-up [count] [type]    # Spawn N agents (incremental)
#   ./scripts/auto-scaler.sh scale-down [agent-name]    # Teardown specific agent
#   ./scripts/auto-scaler.sh check-idle [timeout]       # Find idle agents
#   ./scripts/auto-scaler.sh auto [interval]            # Auto-scaling loop
#
# Part of: Phase 1 NTM Implementation (bd-3ii)

set -euo pipefail

# Project root and paths
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIDS_DIR="$PROJECT_ROOT/pids"
AGENT_REGISTRY="$PROJECT_ROOT/scripts/agent-registry.sh"
SPAWN_SWARM="$PROJECT_ROOT/scripts/spawn-swarm.sh"
TASK_ANALYZER="$PROJECT_ROOT/scripts/task-analyzer.sh"
MATCH_ENGINE="$PROJECT_ROOT/scripts/match-engine.sh"
LIFECYCLE_TRACKER="$PROJECT_ROOT/scripts/task-lifecycle-tracker.sh"

# Autoscaler state directory
SCALER_DIR="$PROJECT_ROOT/.beads/autoscaler"
mkdir -p "$SCALER_DIR"

# Activity tracking file (JSONL format)
ACTIVITY_FILE="$SCALER_DIR/agent-activity.jsonl"
touch "$ACTIVITY_FILE"

# Default configuration
DEFAULT_IDLE_TIMEOUT=1800  # 30 minutes in seconds
DEFAULT_CHECK_INTERVAL=300  # 5 minutes
MIN_AGENTS=0
MAX_AGENTS=8
SCALE_UP_THRESHOLD=3  # Tasks per agent ratio to trigger scale-up
SCALE_DOWN_THRESHOLD=1  # Tasks per agent ratio to trigger scale-down

# Colors
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
  analyze                       Analyze queue and recommend scaling actions
  scale-up [count] [type]       Spawn N agents of specified type (incremental)
  scale-down <agent-name>       Teardown specific agent gracefully
  check-idle [timeout]          Find agents idle longer than timeout (default: 30min)
  auto [interval]               Run auto-scaling loop (default: 5min intervals)
  track <agent> <event>         Track agent activity event
  help                          Show this help message

Queue Analysis:
  - Analyzes ready tasks in Beads queue
  - Determines required agent types from task capabilities
  - Recommends scale-up/down actions based on queue depth

Incremental Spawning:
  - Spawns agents one at a time (not batch)
  - Uses agent type registry to determine capabilities
  - Integrates with spawn-swarm.sh and agent-registry.sh

Idle Detection:
  - Tracks agent activity (task claims, completions)
  - Detects agents idle longer than threshold
  - Recommends teardown for idle agents

Auto-Teardown:
  - Gracefully terminates idle agents
  - Cleans up tmux panes, state files, registrations

Configuration:
  MIN_AGENTS=$MIN_AGENTS (minimum agents to keep running)
  MAX_AGENTS=$MAX_AGENTS (maximum agents to spawn)
  IDLE_TIMEOUT=$DEFAULT_IDLE_TIMEOUT seconds (30 minutes)
  CHECK_INTERVAL=$DEFAULT_CHECK_INTERVAL seconds (5 minutes)

Examples:
  $(basename "$0") analyze                    # Analyze queue composition
  $(basename "$0") scale-up 2 backend         # Spawn 2 backend agents
  $(basename "$0") scale-down StormyRaven     # Teardown StormyRaven
  $(basename "$0") check-idle 1800            # Find agents idle >30min
  $(basename "$0") auto 300                   # Auto-scale every 5 minutes

EOF
}

#######################################
# Get current timestamp (epoch seconds)
#######################################
get_timestamp() {
    date +%s
}

#######################################
# Track agent activity event
# Arguments:
#   $1 - Agent name
#   $2 - Event type (spawn, claim, complete, idle, teardown)
#######################################
track_activity() {
    local agent_name="$1"
    local event_type="$2"
    local timestamp=$(get_timestamp)

    # Append to activity log (JSONL)
    echo "{\"timestamp\": $timestamp, \"agent\": \"$agent_name\", \"event\": \"$event_type\"}" >> "$ACTIVITY_FILE"
}

#######################################
# Get last activity timestamp for agent
# Arguments:
#   $1 - Agent name
# Returns: Epoch timestamp of last activity (or 0 if none)
#######################################
get_last_activity() {
    local agent_name="$1"

    # Find most recent activity for this agent
    local last_ts=$(grep "\"agent\": \"$agent_name\"" "$ACTIVITY_FILE" 2>/dev/null | tail -1 | jq -r '.timestamp' 2>/dev/null || echo "0")

    # If empty or invalid, return 0
    if [ -z "$last_ts" ] || [ "$last_ts" = "null" ]; then
        echo "0"
    else
        echo "$last_ts"
    fi
}

#######################################
# Get count of active agents
# Returns: Number of active agents
#######################################
get_active_agent_count() {
    if [ ! -f "$AGENT_REGISTRY" ]; then
        echo "0"
        return
    fi

    local count=$("$AGENT_REGISTRY" active 2>/dev/null | wc -l | tr -d ' ')
    echo "${count:-0}"
}

#######################################
# Analyze queue composition
# Returns: JSON with queue analysis
#######################################
analyze_queue() {
    # Get ready tasks (use br ready for unblocked tasks only)
    local ready_tasks=$(br ready 2>/dev/null | grep -o 'bd-[a-z0-9]*' || echo "")

    if [ -z "$ready_tasks" ]; then
        echo '{"ready_tasks": 0, "recommendations": [], "types_needed": {}}'
        return
    fi

    # Count tasks
    local task_count=$(echo "$ready_tasks" | wc -l | tr -d ' ')

    # Analyze required capabilities for each task
    # Using individual counters instead of associative array (bash 3.2 compatibility)
    local general_count=0
    local backend_count=0
    local frontend_count=0
    local devops_count=0
    local docs_count=0
    local qa_count=0

    if [ -f "$TASK_ANALYZER" ]; then
        while IFS= read -r task_id; do
            if [ -n "$task_id" ]; then
                # Get task skills
                local skills=$("$TASK_ANALYZER" skills "$task_id" 2>/dev/null || echo "general")

                # Map skills to agent types
                # Simple heuristic: if task has specific skills, prefer specialized type
                if echo "$skills" | grep -qE "(python|api|database)"; then
                    backend_count=$((backend_count + 1))
                elif echo "$skills" | grep -qE "(javascript|typescript|react|css)"; then
                    frontend_count=$((frontend_count + 1))
                elif echo "$skills" | grep -qE "(docker|kubernetes|ci-cd)"; then
                    devops_count=$((devops_count + 1))
                elif echo "$skills" | grep -qE "(documentation|markdown)"; then
                    docs_count=$((docs_count + 1))
                elif echo "$skills" | grep -qE "(testing)"; then
                    qa_count=$((qa_count + 1))
                else
                    general_count=$((general_count + 1))
                fi
            fi
        done <<< "$ready_tasks"
    else
        # Fallback: assume all general
        general_count=$task_count
    fi

    # Get current active agent count
    local active_agents=$(get_active_agent_count)

    # Get lifecycle feedback data (bd-2pfa integration)
    local completion_rate=0
    local avg_cycle_time=0
    local success_rate=100
    local active_tasks=0

    if [ -f "$LIFECYCLE_TRACKER" ]; then
        local feedback=$("$LIFECYCLE_TRACKER" feed-autoscaler 2>/dev/null || echo '{}')
        completion_rate=$(echo "$feedback" | jq -r '.completion_rate // 0' 2>/dev/null || echo "0")
        avg_cycle_time=$(echo "$feedback" | jq -r '.avg_cycle_time // 0' 2>/dev/null || echo "0")
        success_rate=$(echo "$feedback" | jq -r '.success_rate // 100' 2>/dev/null || echo "100")
        active_tasks=$(echo "$feedback" | jq -r '.active_tasks // 0' 2>/dev/null || echo "0")
    fi

    # Calculate recommendations
    local recommendations=()

    # Determine if we need to scale up or down
    if [ $task_count -gt 0 ] && [ $active_agents -lt $MAX_AGENTS ]; then
        # Scale up if tasks/agent ratio > threshold
        local ratio=$(echo "scale=2; $task_count / ($active_agents + 1)" | bc 2>/dev/null || echo "0")
        local should_scale=$(echo "$ratio > $SCALE_UP_THRESHOLD" | bc -l 2>/dev/null || echo "0")

        if [ "$should_scale" = "1" ]; then
            # Determine which type to spawn (highest count)
            local max_type="general"
            local max_count=$general_count

            if [ $backend_count -gt $max_count ]; then
                max_type="backend"
                max_count=$backend_count
            fi
            if [ $frontend_count -gt $max_count ]; then
                max_type="frontend"
                max_count=$frontend_count
            fi
            if [ $devops_count -gt $max_count ]; then
                max_type="devops"
                max_count=$devops_count
            fi
            if [ $docs_count -gt $max_count ]; then
                max_type="docs"
                max_count=$docs_count
            fi
            if [ $qa_count -gt $max_count ]; then
                max_type="qa"
                max_count=$qa_count
            fi

            # Recommend spawning 1-3 agents based on queue depth and completion velocity
            local spawn_count=1
            if [ $task_count -ge 15 ]; then
                spawn_count=3
            elif [ $task_count -ge 10 ]; then
                spawn_count=2
            fi

            # Adjust spawn count based on lifecycle feedback (bd-2pfa)
            # If we have many active tasks but low completion rate, spawn more aggressively
            if [ "$active_tasks" -ge 3 ] && [ "$completion_rate" -lt 2 ]; then
                # Many tasks in progress but slow completion → need more agents
                spawn_count=$((spawn_count + 1))
            fi

            # If success rate is very low, add warning but still scale
            # (agents might be stuck, more agents can help with handoffs)
            if [ "$(echo "$success_rate < 50" | bc -l 2>/dev/null)" = "1" ]; then
                recommendations+=("warning:low-success-rate:${success_rate}%")
            fi

            # Don't exceed MAX_AGENTS
            local available_slots=$((MAX_AGENTS - active_agents))
            if [ $spawn_count -gt $available_slots ]; then
                spawn_count=$available_slots
            fi

            if [ $spawn_count -gt 0 ]; then
                recommendations+=("scale-up:$spawn_count:$max_type")
            fi
        fi
    elif [ $task_count -eq 0 ] && [ $active_agents -gt $MIN_AGENTS ]; then
        # Scale down if no tasks and agents are idle
        recommendations+=("check-idle:teardown")
    fi

    # Build JSON output manually
    cat <<EOF
{
  "ready_tasks": $task_count,
  "active_agents": $active_agents,
  "ratio": $(echo "scale=2; $task_count / ($active_agents + 1)" | bc 2>/dev/null || echo "0"),
  "lifecycle_feedback": {
    "completion_rate": $completion_rate,
    "avg_cycle_time": $avg_cycle_time,
    "success_rate": $success_rate,
    "active_tasks": $active_tasks
  },
  "types_needed": {
    "general": $general_count,
    "backend": $backend_count,
    "frontend": $frontend_count,
    "devops": $devops_count,
    "docs": $docs_count,
    "qa": $qa_count
  },
  "recommendations": [
EOF

    # Add recommendations
    local first=true
    for rec in "${recommendations[@]+"${recommendations[@]}"}"; do
        if [ "$first" = true ]; then
            echo -n "    \"$rec\""
            first=false
        else
            echo ","
            echo -n "    \"$rec\""
        fi
    done
    echo ""
    echo "  ]"
    echo "}"
}

#######################################
# Scale up: spawn N agents incrementally
# Arguments:
#   $1 - Count (default: 1)
#   $2 - Agent type (default: general)
#######################################
scale_up() {
    local count="${1:-1}"
    local agent_type="${2:-general}"

    print_msg BLUE "Scaling up: spawning $count agent(s) of type '$agent_type'..."

    # Validate agent type
    if [ -f "$AGENT_REGISTRY" ]; then
        if ! "$AGENT_REGISTRY" validate "$agent_type" >/dev/null 2>&1; then
            print_msg RED "Error: Invalid agent type '$agent_type'"
            return 1
        fi
    fi

    # Check if we can spawn (MAX_AGENTS limit)
    local active_agents=$(get_active_agent_count)
    local available_slots=$((MAX_AGENTS - active_agents))

    if [ $available_slots -le 0 ]; then
        print_msg YELLOW "Cannot scale up: already at MAX_AGENTS ($MAX_AGENTS)"
        return 1
    fi

    if [ $count -gt $available_slots ]; then
        print_msg YELLOW "Reducing spawn count from $count to $available_slots (MAX_AGENTS limit)"
        count=$available_slots
    fi

    # Spawn agents incrementally (one at a time)
    for ((i=0; i<count; i++)); do
        print_msg BLUE "Spawning agent $((i+1))/$count..."

        # Use spawn-swarm.sh to spawn a single agent
        if [ -f "$SPAWN_SWARM" ]; then
            # Generate unique session name
            local session_name="autoscale-$agent_type-$(date +%s)"

            # Spawn single agent
            "$SPAWN_SWARM" 1 "$session_name" --type "$agent_type" >/dev/null 2>&1

            if [ $? -eq 0 ]; then
                # Get agent name from state file
                local state_file="$PIDS_DIR/swarm-${session_name}.state"
                if [ -f "$state_file" ]; then
                    local agent_name=$(jq -r '.agents[0].name' "$state_file" 2>/dev/null || echo "unknown")

                    # Track spawn activity
                    track_activity "$agent_name" "spawn"

                    print_msg GREEN "✓ Spawned $agent_name (type: $agent_type, session: $session_name)"
                else
                    print_msg YELLOW "⚠ Agent spawned but state file not found"
                fi
            else
                print_msg RED "✗ Failed to spawn agent"
                return 1
            fi
        else
            print_msg RED "Error: spawn-swarm.sh not found"
            return 1
        fi

        # Brief delay between spawns to avoid resource contention
        if [ $i -lt $((count-1)) ]; then
            sleep 2
        fi
    done

    print_msg GREEN "Scale-up complete: spawned $count agent(s)"
}

#######################################
# Scale down: teardown specific agent
# Arguments:
#   $1 - Agent name
#######################################
scale_down() {
    local agent_name="$1"

    if [ -z "$agent_name" ]; then
        print_msg RED "Error: Agent name required for scale-down"
        return 1
    fi

    print_msg BLUE "Scaling down: tearing down $agent_name..."

    # Track teardown activity
    track_activity "$agent_name" "teardown"

    # Find agent's tmux session and pane
    local sessions=$(find "$PIDS_DIR" -name "swarm-*.state" -type f 2>/dev/null || true)

    local found=false
    while IFS= read -r state_file; do
        if [ -f "$state_file" ]; then
            # Check if agent is in this session
            local agent_in_session=$(jq -r --arg name "$agent_name" '.agents[] | select(.name == $name) | .name' "$state_file" 2>/dev/null || echo "")

            if [ "$agent_in_session" = "$agent_name" ]; then
                found=true

                # Get session and pane info
                local session=$(jq -r '.session' "$state_file" 2>/dev/null)
                local pane_id=$(jq -r --arg name "$agent_name" '.agents[] | select(.name == $name) | .pane_id' "$state_file" 2>/dev/null)

                # Kill the tmux pane
                if [ -n "$pane_id" ] && tmux list-panes -a -F "#{pane_id}" 2>/dev/null | grep -q "^$pane_id$"; then
                    tmux kill-pane -t "$pane_id" 2>/dev/null || true
                    print_msg GREEN "✓ Killed tmux pane $pane_id"
                fi

                # Unregister agent from registry
                if [ -f "$AGENT_REGISTRY" ]; then
                    "$AGENT_REGISTRY" unregister "$agent_name" 2>/dev/null || true
                    print_msg GREEN "✓ Unregistered $agent_name from registry"
                fi

                # Clean up state file if this was the only agent in the session
                local agent_count=$(jq -r '.count' "$state_file" 2>/dev/null || echo "0")
                if [ "$agent_count" -eq 1 ]; then
                    rm -f "$state_file"
                    print_msg GREEN "✓ Cleaned up state file"

                    # Kill entire session if it still exists
                    if tmux has-session -t "$session" 2>/dev/null; then
                        tmux kill-session -t "$session" 2>/dev/null || true
                    fi
                fi

                break
            fi
        fi
    done <<< "$sessions"

    if [ "$found" = false ]; then
        print_msg YELLOW "⚠ Agent $agent_name not found in any session"
        return 1
    fi

    print_msg GREEN "Scale-down complete: $agent_name torn down"
}

#######################################
# Check for idle agents
# Arguments:
#   $1 - Idle timeout in seconds (default: 1800 = 30min)
# Returns: List of idle agent names
#######################################
check_idle() {
    local timeout="${1:-$DEFAULT_IDLE_TIMEOUT}"
    local now=$(get_timestamp)
    local idle_threshold=$((now - timeout))

    # Get all active agents
    local active_agents=$("$AGENT_REGISTRY" active 2>/dev/null || echo "")

    if [ -z "$active_agents" ]; then
        return 0
    fi

    local idle_agents=()

    while IFS= read -r agent_name; do
        if [ -n "$agent_name" ]; then
            # Get last activity for this agent
            local last_activity=$(get_last_activity "$agent_name")

            # If no activity recorded, use current time (just spawned)
            if [ "$last_activity" -eq 0 ]; then
                last_activity=$now
                track_activity "$agent_name" "spawn"
            fi

            # Check if idle
            if [ $last_activity -lt $idle_threshold ]; then
                local idle_duration=$((now - last_activity))
                idle_agents+=("$agent_name:$idle_duration")
            fi
        fi
    done <<< "$active_agents"

    # Print idle agents
    if [ ${#idle_agents[@]} -gt 0 ]; then
        for entry in "${idle_agents[@]}"; do
            local agent_name="${entry%%:*}"
            local idle_duration="${entry##*:}"
            local idle_minutes=$((idle_duration / 60))
            echo "$agent_name (idle: ${idle_minutes}min)"
        done
    fi
}

#######################################
# Auto-scaling loop
# Arguments:
#   $1 - Check interval in seconds (default: 300 = 5min)
#######################################
auto_scale() {
    local interval="${1:-$DEFAULT_CHECK_INTERVAL}"

    print_msg BLUE "Starting auto-scaling loop (interval: ${interval}s)..."
    print_msg BLUE "Press Ctrl+C to stop"
    echo ""

    while true; do
        local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
        echo "[$timestamp] Checking queue and agent activity..."

        # Analyze queue
        local analysis=$(analyze_queue)
        local ready_tasks=$(echo "$analysis" | jq -r '.ready_tasks')
        local active_agents=$(echo "$analysis" | jq -r '.active_agents')
        local recommendations=$(echo "$analysis" | jq -r '.recommendations[]' 2>/dev/null || echo "")

        echo "  Ready tasks: $ready_tasks"
        echo "  Active agents: $active_agents"

        # Execute recommendations
        if [ -n "$recommendations" ]; then
            while IFS= read -r rec; do
                if [ -n "$rec" ]; then
                    local action="${rec%%:*}"
                    local rest="${rec#*:}"

                    case "$action" in
                        scale-up)
                            local count="${rest%%:*}"
                            local type="${rest##*:}"
                            echo "  → Recommendation: Scale up $count $type agent(s)"
                            scale_up "$count" "$type"
                            ;;
                        check-idle)
                            echo "  → Recommendation: Check for idle agents"
                            local idle=$(check_idle)
                            if [ -n "$idle" ]; then
                                echo "  → Idle agents detected:"
                                echo "$idle" | while IFS= read -r line; do
                                    echo "      $line"
                                    local agent="${line%% (*}"
                                    # Auto-teardown idle agents
                                    if [ $active_agents -gt $MIN_AGENTS ]; then
                                        echo "      → Tearing down $agent..."
                                        scale_down "$agent"
                                    fi
                                done
                            else
                                echo "  → No idle agents found"
                            fi
                            ;;
                    esac
                fi
            done <<< "$recommendations"
        else
            echo "  → No scaling actions needed"
        fi

        echo ""
        sleep "$interval"
    done
}

#######################################
# Command: analyze
#######################################
cmd_analyze() {
    local analysis=$(analyze_queue)

    echo "Queue Analysis:"
    echo "==============="
    echo "$analysis" | jq '.'
    echo ""

    # Pretty-print recommendations
    local recommendations=$(echo "$analysis" | jq -r '.recommendations[]' 2>/dev/null || echo "")

    if [ -n "$recommendations" ]; then
        echo "Recommendations:"
        while IFS= read -r rec; do
            if [ -n "$rec" ]; then
                echo "  - $rec"
            fi
        done <<< "$recommendations"
    else
        echo "Recommendations: None (system balanced)"
    fi
}

#######################################
# Command: track
#######################################
cmd_track() {
    if [ $# -lt 2 ]; then
        print_msg RED "Error: 'track' requires agent name and event type"
        usage
        exit 1
    fi

    local agent_name="$1"
    local event_type="$2"

    track_activity "$agent_name" "$event_type"
    echo "Tracked: $agent_name → $event_type"
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
            cmd_analyze
            ;;
        scale-up)
            scale_up "$@"
            ;;
        scale-down)
            if [ $# -lt 1 ]; then
                print_msg RED "Error: 'scale-down' requires agent name"
                usage
                exit 1
            fi
            scale_down "$@"
            ;;
        check-idle)
            check_idle "$@"
            ;;
        auto)
            auto_scale "$@"
            ;;
        track)
            cmd_track "$@"
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
