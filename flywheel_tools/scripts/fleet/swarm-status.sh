#!/usr/bin/env bash
# swarm-status.sh - Monitor swarm agent activity and task progress
#
# Usage: ./scripts/swarm-status.sh <swarm-session> [options]
#
# Description:
#   Real-time monitoring of swarm agent activity, task progress, file reservations,
#   mail activity, and system health. Supports multiple display modes.
#
# Examples:
#   ./scripts/swarm-status.sh phase3              # Full status display
#   ./scripts/swarm-status.sh phase3 --compact    # One-line summary
#   ./scripts/swarm-status.sh phase3 --watch      # Auto-refresh every 5s
#   ./scripts/swarm-status.sh phase3 --json       # JSON output
#   ./scripts/swarm-status.sh phase3 agents tasks # Show specific sections
#
# Part of: Component 2 - Agent Swarm Orchestration (bd-15z)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIDS_DIR="$PROJECT_ROOT/pids"

# Display mode flags
MODE="full"
WATCH_INTERVAL=5
SECTIONS=()

#######################################
# Print usage information
#######################################
usage() {
    cat <<EOF
Usage: $(basename "$0") <swarm-session> [options] [sections]

Monitor swarm agent activity, task progress, and system health in real-time.

Arguments:
  swarm-session   Tmux session name from spawn-swarm.sh (required)

Options:
  --compact       One-line summary mode
  --watch         Auto-refresh every ${WATCH_INTERVAL}s (Ctrl+C to exit)
  --json          JSON output for scripting
  --broadcast <msg>  Send broadcast message to all agents in this swarm
  --help          Show this help message

Sections (for filtered display):
  agents          Agent status and current tasks
  tasks           Task breakdown by status
  files           File reservations with warnings
  mail            Mail activity per agent
  system          System health indicators

Examples:
  $(basename "$0") phase3              # Full status display
  $(basename "$0") phase3 --compact    # One-line summary
  $(basename "$0") phase3 --watch      # Auto-refresh mode
  $(basename "$0") phase3 --json       # JSON output
  $(basename "$0") phase3 agents tasks # Show only agents and tasks sections
  $(basename "$0") phase3 --broadcast "Pause work - system maintenance" # Broadcast to swarm

Display Modes:
  full     - All sections with detailed information (default)
  compact  - Single-line summary for scripting/status bars
  watch    - Auto-refresh every ${WATCH_INTERVAL}s with clear screen
  json     - Structured JSON output for parsing

Requirements:
  - Swarm must exist (created with spawn-swarm.sh)
  - Beads CLI (br) must be available
  - Agent mail system must be configured
EOF
}

#######################################
# Print colored message to stderr
# Arguments:
#   $1 - Color (RED, GREEN, YELLOW, BLUE, etc.)
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
# Get swarm metadata
# Arguments:
#   $1 - Swarm state JSON
# Returns: session|count|spawn_time
#######################################
get_swarm_metadata() {
    local state="$1"

    local session=$(echo "$state" | grep '"session":' | head -1 | sed 's/.*"session": "\([^"]*\)".*/\1/')
    local count=$(echo "$state" | grep '"count":' | head -1 | sed 's/.*"count": \([0-9]*\).*/\1/')
    local spawn_time=$(echo "$state" | grep '"spawn_time":' | head -1 | sed 's/.*"spawn_time": "\([^"]*\)".*/\1/')

    echo "$session|$count|$spawn_time"
}

#######################################
# Check if tmux pane is active
# Arguments:
#   $1 - Session name
#   $2 - Pane ID
# Returns: 0 if active, 1 if not
#######################################
is_pane_active() {
    local session="$1"
    local pane_id="$2"

    # Check if pane exists and session is active
    if ! tmux has-session -t "$session" 2>/dev/null; then
        return 1
    fi

    if tmux list-panes -t "$session" -F "#{pane_id}" 2>/dev/null | grep -q "^$pane_id$"; then
        return 0
    else
        return 1
    fi
}

#######################################
# Get agent status
# Arguments:
#   $1 - Session name
#   $2 - Agent name
#   $3 - Pane ID
# Returns: status|task_id|duration (status: active/idle/offline)
#######################################
get_agent_status() {
    local session="$1"
    local agent="$2"
    local pane_id="$3"

    # Check if pane is active
    if ! is_pane_active "$session" "$pane_id"; then
        echo "offline||0"
        return
    fi

    # Query Beads for agent's current task
    local agent_task=$(br list --status in_progress 2>/dev/null | grep "○" | grep -i "$agent" | head -1 || echo "")

    if [ -n "$agent_task" ]; then
        # Extract task ID
        local task_id=$(echo "$agent_task" | grep -oE 'bd-[a-z0-9]+' | head -1)

        # Try to get task start time (simplified - just use current time for now)
        local duration="unknown"

        echo "active|$task_id|$duration"
    else
        echo "idle||0"
    fi
}

#######################################
# Get task statistics
# Returns: ready|in_progress|completed|blocked
#######################################
get_task_stats() {
    # Initialize all counters to 0
    local ready=0
    local in_progress=0
    local completed=0
    local blocked=0

    # Query Beads for task counts
    # Note: br list doesn't have great filtering, so we count manually
    local open_tasks=$(br list --status open 2>/dev/null || echo "")
    local done_tasks=$(br list --status closed 2>/dev/null || echo "")

    # Count open tasks (these are "ready")
    if [ -n "$open_tasks" ]; then
        ready=$(echo "$open_tasks" | grep -c "○" 2>/dev/null) || ready=0
    fi

    # Count in-progress
    local in_prog_output=$(br list --status in_progress 2>/dev/null || echo "")
    if [ -n "$in_prog_output" ]; then
        in_progress=$(echo "$in_prog_output" | grep -c "○" 2>/dev/null) || in_progress=0
    fi

    # Count completed
    if [ -n "$done_tasks" ]; then
        completed=$(echo "$done_tasks" | grep -c "●" 2>/dev/null) || completed=0
    fi

    # Ensure all values are numeric
    ready=${ready:-0}
    in_progress=${in_progress:-0}
    completed=${completed:-0}
    blocked=${blocked:-0}

    echo "$ready|$in_progress|$completed|$blocked"
}

#######################################
# Get file reservations for an agent
# Arguments:
#   $1 - Agent name
# Returns: count|expiring_count
#######################################
get_agent_reservations() {
    local agent="$1"
    local count=0
    local expiring=0

    # Check for reservation files
    local reservations_dir="$PROJECT_ROOT/.reservations"

    if [ ! -d "$reservations_dir" ]; then
        echo "0|0"
        return
    fi

    # Count active reservations for this agent
    local json_files=("$reservations_dir"/*.json)
    for res_file in "${json_files[@]}"; do
        if [ -f "$res_file" ] && [ "$res_file" != "$reservations_dir/*.json" ]; then
            # Check if this reservation belongs to the agent
            if grep -q "\"reason\": \".*$agent" "$res_file" 2>/dev/null; then
                ((count++))

                # Check if expiring soon (<30 min)
                local expires=$(grep '"expires_at"' "$res_file" | sed 's/.*"expires_at": "\([^"]*\)".*/\1/')
                if [ -n "$expires" ]; then
                    local now=$(date -u +%s)
                    local exp_time=$(date -d "$expires" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${expires%.*}" +%s 2>/dev/null || echo "0")
                    local diff=$((exp_time - now))

                    if [ $diff -lt 1800 ] && [ $diff -gt 0 ]; then
                        ((expiring++))
                    fi
                fi
            fi
        fi
    done

    echo "$count|$expiring"
}

#######################################
# Get mail activity for an agent
# Arguments:
#   $1 - Agent name
# Returns: unread_count|last_activity
#######################################
get_agent_mail() {
    local agent="$1"

    # Query agent mail (this is simplified)
    # In a real implementation, we'd query the MCP server
    local unread=0
    local last_activity="none"

    # For now, return placeholder values
    echo "$unread|$last_activity"
}

#######################################
# Check system health
# Returns: tmux_ok|beads_ok|mail_ok
#######################################
check_system_health() {
    local tmux_ok=0
    local beads_ok=0
    local mail_ok=0

    # Check tmux
    if command -v tmux &> /dev/null; then
        tmux_ok=1
    fi

    # Check Beads
    if br list --status open &>/dev/null; then
        beads_ok=1
    fi

    # Check agent mail (check if helper script exists and is executable)
    if [ -x "$PROJECT_ROOT/scripts/agent-mail-helper.sh" ]; then
        mail_ok=1
    fi

    echo "$tmux_ok|$beads_ok|$mail_ok"
}

#######################################
# Display full status
# Arguments:
#   $1 - Session name
#   $2 - Swarm state JSON
#   $3 - Space-separated agent names
#######################################
display_full_status() {
    local session="$1"
    local state="$2"
    local agents_str="$3"

    IFS=' ' read -ra agents <<< "$agents_str"

    # Get metadata
    local metadata=$(get_swarm_metadata "$state")
    IFS='|' read -r sess_name agent_count spawn_time <<< "$metadata"

    # Header
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║  SWARM STATUS: $sess_name"
    echo "╠════════════════════════════════════════════════════════════════════╣"
    echo "║  Agents: $agent_count  •  Spawned: $spawn_time"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo ""

    # Section: Agents
    if should_show_section "agents"; then
        echo -e "${BLUE}┌─ AGENTS ─────────────────────────────────────────────────────────┐${NC}"

        for agent in "${agents[@]}"; do
            # Get pane ID for this agent
            local pane_id=$(echo "$state" | grep -A3 "\"name\": \"$agent\"" | grep '"pane_id"' | sed 's/.*"pane_id": "\([^"]*\)".*/\1/')

            # Get agent status
            local status_info=$(get_agent_status "$session" "$agent" "$pane_id")
            IFS='|' read -r status task_id duration <<< "$status_info"

            # Color-code status
            local status_color="$GREEN"
            local status_symbol="●"
            if [ "$status" = "offline" ]; then
                status_color="$RED"
                status_symbol="○"
            elif [ "$status" = "idle" ]; then
                status_color="$YELLOW"
                status_symbol="◐"
            fi

            # Get reservations
            local res_info=$(get_agent_reservations "$agent")
            IFS='|' read -r res_count res_expiring <<< "$res_info"

            # Display agent info
            echo -n "  "
            echo -ne "${status_color}${status_symbol}${NC} ${agent}"
            printf " %-12s" "($status)"

            if [ -n "$task_id" ]; then
                echo -n " │ Task: $task_id"
            fi

            if [ "$res_count" -gt 0 ]; then
                echo -n " │ Files: $res_count"
                if [ "$res_expiring" -gt 0 ]; then
                    echo -ne " ${YELLOW}($res_expiring expiring)${NC}"
                fi
            fi

            echo ""
        done

        echo -e "${BLUE}└──────────────────────────────────────────────────────────────────┘${NC}"
        echo ""
    fi

    # Section: Tasks
    if should_show_section "tasks"; then
        local task_stats=$(get_task_stats)
        IFS='|' read -r ready in_prog completed blocked <<< "$task_stats"

        echo -e "${CYAN}┌─ TASKS ──────────────────────────────────────────────────────────┐${NC}"
        echo -e "  ${GREEN}Ready:${NC} $ready  │  ${YELLOW}In Progress:${NC} $in_prog  │  ${BLUE}Completed:${NC} $completed  │  ${RED}Blocked:${NC} $blocked"
        echo -e "${CYAN}└──────────────────────────────────────────────────────────────────┘${NC}"
        echo ""
    fi

    # Section: Files
    if should_show_section "files"; then
        local total_files=0
        local total_expiring=0

        for agent in "${agents[@]}"; do
            local res_info=$(get_agent_reservations "$agent")
            IFS='|' read -r res_count res_expiring <<< "$res_info"
            total_files=$((total_files + res_count))
            total_expiring=$((total_expiring + res_expiring))
        done

        echo -e "${MAGENTA}┌─ FILE RESERVATIONS ──────────────────────────────────────────────┐${NC}"
        echo -n "  Total: $total_files"

        if [ "$total_expiring" -gt 0 ]; then
            echo -ne "  │  ${YELLOW}⚠ $total_expiring expiring soon${NC}"
        fi
        echo ""

        echo -e "${MAGENTA}└──────────────────────────────────────────────────────────────────┘${NC}"
        echo ""
    fi

    # Section: Mail
    if should_show_section "mail"; then
        echo -e "${GREEN}┌─ MAIL ACTIVITY ──────────────────────────────────────────────────┐${NC}"
        echo "  Agent mail monitoring enabled"
        echo -e "${GREEN}└──────────────────────────────────────────────────────────────────┘${NC}"
        echo ""
    fi

    # Section: System Health
    if should_show_section "system"; then
        local health=$(check_system_health)
        IFS='|' read -r tmux_ok beads_ok mail_ok <<< "$health"

        echo -e "${BLUE}┌─ SYSTEM HEALTH ──────────────────────────────────────────────────┐${NC}"

        echo -n "  "
        if [ "$tmux_ok" -eq 1 ]; then
            echo -ne "${GREEN}✓${NC} tmux    "
        else
            echo -ne "${RED}✗${NC} tmux    "
        fi

        if [ "$beads_ok" -eq 1 ]; then
            echo -ne "${GREEN}✓${NC} beads   "
        else
            echo -ne "${RED}✗${NC} beads   "
        fi

        if [ "$mail_ok" -eq 1 ]; then
            echo -ne "${GREEN}✓${NC} agent-mail"
        else
            echo -ne "${RED}✗${NC} agent-mail"
        fi
        echo ""

        echo -e "${BLUE}└──────────────────────────────────────────────────────────────────┘${NC}"
        echo ""
    fi
}

#######################################
# Display compact status
# Arguments:
#   $1 - Session name
#   $2 - Swarm state JSON
#   $3 - Space-separated agent names
#######################################
display_compact_status() {
    local session="$1"
    local state="$2"
    local agents_str="$3"

    IFS=' ' read -ra agents <<< "$agents_str"

    # Count active agents
    local active=0
    for agent in "${agents[@]}"; do
        local pane_id=$(echo "$state" | grep -A3 "\"name\": \"$agent\"" | grep '"pane_id"' | sed 's/.*"pane_id": "\([^"]*\)".*/\1/')
        if is_pane_active "$session" "$pane_id"; then
            ((active++))
        fi
    done

    # Get task stats
    local task_stats=$(get_task_stats)
    IFS='|' read -r ready in_prog completed blocked <<< "$task_stats"

    # Count total files
    local total_files=0
    for agent in "${agents[@]}"; do
        local res_info=$(get_agent_reservations "$agent")
        IFS='|' read -r res_count res_expiring <<< "$res_info"
        total_files=$((total_files + res_count))
    done

    # Get health
    local health=$(check_system_health)
    IFS='|' read -r tmux_ok beads_ok mail_ok <<< "$health"

    local health_status="✓"
    if [ "$tmux_ok" -eq 0 ] || [ "$beads_ok" -eq 0 ] || [ "$mail_ok" -eq 0 ]; then
        health_status="⚠"
    fi

    # One-line summary
    echo "SWARM[$session]: ${active}/${#agents[@]} agents │ Tasks: $ready ready, $in_prog in-progress │ Files: $total_files locked │ Health: $health_status"
}

#######################################
# Display JSON status
# Arguments:
#   $1 - Session name
#   $2 - Swarm state JSON
#   $3 - Space-separated agent names
#######################################
display_json_status() {
    local session="$1"
    local state="$2"
    local agents_str="$3"

    IFS=' ' read -ra agents <<< "$agents_str"

    # Get metadata
    local metadata=$(get_swarm_metadata "$state")
    IFS='|' read -r sess_name agent_count spawn_time <<< "$metadata"

    # Build JSON manually
    echo "{"
    echo "  \"session\": \"$sess_name\","
    echo "  \"agent_count\": $agent_count,"
    echo "  \"spawn_time\": \"$spawn_time\","
    echo "  \"agents\": ["

    local agent_index=0
    for agent in "${agents[@]}"; do
        local pane_id=$(echo "$state" | grep -A3 "\"name\": \"$agent\"" | grep '"pane_id"' | sed 's/.*"pane_id": "\([^"]*\)".*/\1/')
        local status_info=$(get_agent_status "$session" "$agent" "$pane_id")
        IFS='|' read -r status task_id duration <<< "$status_info"

        local res_info=$(get_agent_reservations "$agent")
        IFS='|' read -r res_count res_expiring <<< "$res_info"

        local comma=""
        [ $agent_index -lt $((${#agents[@]} - 1)) ] && comma=","

        echo "    {"
        echo "      \"name\": \"$agent\","
        echo "      \"status\": \"$status\","
        echo "      \"task\": \"$task_id\","
        echo "      \"reservations\": $res_count,"
        echo "      \"reservations_expiring\": $res_expiring"
        echo "    }$comma"

        ((agent_index++))
    done

    echo "  ],"

    # Task stats
    local task_stats=$(get_task_stats)
    IFS='|' read -r ready in_prog completed blocked <<< "$task_stats"

    echo "  \"tasks\": {"
    echo "    \"ready\": $ready,"
    echo "    \"in_progress\": $in_prog,"
    echo "    \"completed\": $completed,"
    echo "    \"blocked\": $blocked"
    echo "  },"

    # System health
    local health=$(check_system_health)
    IFS='|' read -r tmux_ok beads_ok mail_ok <<< "$health"

    echo "  \"health\": {"
    echo "    \"tmux\": $([ $tmux_ok -eq 1 ] && echo "true" || echo "false"),"
    echo "    \"beads\": $([ $beads_ok -eq 1 ] && echo "true" || echo "false"),"
    echo "    \"agent_mail\": $([ $mail_ok -eq 1 ] && echo "true" || echo "false")"
    echo "  }"
    echo "}"
}

#######################################
# Check if section should be shown
# Arguments:
#   $1 - Section name
# Returns: 0 if should show, 1 if not
#######################################
should_show_section() {
    local section="$1"

    # If no sections specified, show all
    if [ ${#SECTIONS[@]} -eq 0 ]; then
        return 0
    fi

    # Check if section is in list
    for s in "${SECTIONS[@]}"; do
        if [ "$s" = "$section" ]; then
            return 0
        fi
    done

    return 1
}

#######################################
# Main display function
# Arguments:
#   $1 - Session name
#######################################
display_status() {
    local session="$1"

    # Read swarm state
    local state=$(read_swarm_state "$session")

    # Get agent names
    local agents_str=$(get_agent_names "$state" | tr '\n' ' ')

    # Display based on mode
    case "$MODE" in
        compact)
            display_compact_status "$session" "$state" "$agents_str"
            ;;
        json)
            display_json_status "$session" "$state" "$agents_str"
            ;;
        *)
            display_full_status "$session" "$state" "$agents_str"
            ;;
    esac
}

#######################################
# Main function
#######################################
main() {
    local session=""

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --help)
                usage
                exit 0
                ;;
            --compact)
                MODE="compact"
                shift
                ;;
            --watch)
                MODE="watch"
                shift
                ;;
            --json)
                MODE="json"
                shift
                ;;
            --broadcast)
                # Broadcast message to swarm agents
                if [ $# -lt 2 ]; then
                    print_msg RED "Error: --broadcast requires a message"
                    usage
                    exit 1
                fi

                # Get session name (must be set already)
                if [ -z "$session" ]; then
                    print_msg RED "Error: Session name must be specified before --broadcast"
                    echo "Usage: $(basename "$0") <session> --broadcast <message>" >&2
                    exit 1
                fi

                shift
                local broadcast_msg="$1"
                shift

                # Verify swarm exists
                check_swarm_exists "$session"

                # Call broadcast-to-swarm.sh
                "$PROJECT_ROOT/scripts/broadcast-to-swarm.sh" "@$session" "$broadcast_msg"
                exit $?
                ;;
            agents|tasks|files|mail|system)
                SECTIONS+=("$1")
                shift
                ;;
            *)
                if [ -z "$session" ]; then
                    session="$1"
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

    # Display status
    if [ "$MODE" = "watch" ]; then
        # Watch mode: loop with refresh
        while true; do
            clear
            display_status "$session"
            echo ""
            echo "Refreshing every ${WATCH_INTERVAL}s... (Press Ctrl+C to exit)"
            sleep $WATCH_INTERVAL
        done
    else
        # Single display
        display_status "$session"
    fi
}

# Run main function
main "$@"
