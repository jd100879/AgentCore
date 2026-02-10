#!/usr/bin/env bash
# teardown-swarm.sh - Gracefully shutdown swarm agents and release resources
#
# Usage: ./scripts/teardown-swarm.sh <swarm-session> [options]
#
# Description:
#   Gracefully shuts down swarm agents, releases file reservations, sends notifications,
#   and generates productivity summary reports. Handles cleanup of tmux sessions and state files.
#
# Examples:
#   ./scripts/teardown-swarm.sh phase3              # Graceful shutdown with prompts
#   ./scripts/teardown-swarm.sh phase3 --force      # Immediate shutdown, no prompts
#   ./scripts/teardown-swarm.sh phase3 --report     # Generate report only, no shutdown
#
# Part of: Component 2 - Agent Swarm Orchestration (bd-3rx)

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

# Options
FORCE_MODE=0
REPORT_ONLY=0
SKIP_MAIL=0
SHUTDOWN_DELAY=10

#######################################
# Print usage information
#######################################
usage() {
    cat <<EOF
Usage: $(basename "$0") <swarm-session> [options]

Gracefully shutdown swarm agents, release resources, and generate summary reports.

Arguments:
  swarm-session   Tmux session name from spawn-swarm.sh (required)

Options:
  --force         Skip confirmations, immediate shutdown
  --report        Generate productivity report only (no shutdown)
  --skip-mail     Skip sending shutdown notifications
  --delay SECS    Shutdown delay in seconds (default: 10)
  --help          Show this help message

Examples:
  $(basename "$0") phase3              # Graceful shutdown with prompts
  $(basename "$0") phase3 --force      # Immediate shutdown, no prompts
  $(basename "$0") phase3 --report     # Generate report only

Pre-Shutdown Checks:
  - Checks for in-progress tasks
  - Checks for active file reservations
  - Warns if uncommitted work detected
  - Prompts for confirmation (unless --force)

Shutdown Sequence:
  1. Verify in-progress tasks
  2. Release all file reservations
  3. Send shutdown notifications via mail (unless --skip-mail)
  4. Kill tmux session after delay
  5. Archive swarm state file
  6. Clean up agent name files
  7. Generate productivity summary

Exit Codes:
  0 - Success
  1 - General error
  2 - Missing state file (swarm doesn't exist)
  3 - User cancelled shutdown
EOF
}

#######################################
# Print colored message
# Arguments:
#   $1 - Color (RED, GREEN, YELLOW, BLUE, CYAN, MAGENTA)
#   $2 - Message
#######################################
print_msg() {
    local color="${!1}"
    local msg="$2"
    echo -e "${color}${msg}${NC}" >&2
}

#######################################
# Read swarm state file
# Arguments:
#   $1 - Session name
# Outputs: JSON state to stdout
#######################################
read_state_file() {
    local session="$1"
    local state_file="$PIDS_DIR/swarm-${session}.state"

    if [ ! -f "$state_file" ]; then
        print_msg RED "Error: Swarm state file not found: $state_file"
        print_msg YELLOW "Swarm '$session' may not exist or was already torn down."
        exit 2
    fi

    cat "$state_file"
}

#######################################
# Check for in-progress tasks
# Arguments:
#   $1 - Session name
#   $2 - Agent names (space-separated)
# Returns: 0 if tasks found, 1 if none
#######################################
check_in_progress_tasks() {
    local session="$1"
    local agents="$2"

    print_msg BLUE "Checking for in-progress tasks..."

    # Query Beads for tasks owned by swarm agents
    local has_tasks=0

    if command -v br &> /dev/null; then
        local tasks_output
        tasks_output=$(br list --format json 2>/dev/null || echo "[]")

        # Check each agent for in-progress tasks
        for agent in $agents; do
            local agent_tasks=$(echo "$tasks_output" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    tasks = [t for t in data if t.get('owner') == '$agent' and t.get('status') == 'open']
    if tasks:
        for t in tasks:
            print(f\"  [{t['id']}] {t['title']} (owner: {t['owner']})\")
except:
    pass
" 2>/dev/null || true)

            if [ -n "$agent_tasks" ]; then
                print_msg YELLOW "  Agent $agent has in-progress tasks:"
                echo "$agent_tasks"
                has_tasks=1
            fi
        done
    fi

    if [ $has_tasks -eq 0 ]; then
        print_msg GREEN "  ✓ No in-progress tasks found"
    fi

    return $has_tasks
}

#######################################
# Check for active file reservations
# Arguments:
#   $1 - Agent names (space-separated)
# Returns: 0 if reservations found, 1 if none
#######################################
check_file_reservations() {
    local agents="$1"

    print_msg BLUE "Checking for active file reservations..."

    local has_reservations=0

    # Check reservations for each agent
    for agent in $agents; do
        local reservations
        reservations=$(AGENT_NAME="$agent" ./scripts/reserve-files.sh list 2>/dev/null | grep -v "^Active reservations" | grep -v "^====" | grep -v "^(No active" || true)

        if [ -n "$reservations" ]; then
            print_msg YELLOW "  Agent $agent has active file reservations:"
            echo "$reservations"
            has_reservations=1
        fi
    done

    if [ $has_reservations -eq 0 ]; then
        print_msg GREEN "  ✓ No active file reservations"
    fi

    return $has_reservations
}

#######################################
# Check for uncommitted work
# Arguments:
#   None
# Returns: 0 if uncommitted changes found, 1 if clean
#######################################
check_uncommitted_work() {
    print_msg BLUE "Checking for uncommitted work..."

    cd "$PROJECT_ROOT"

    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        print_msg YELLOW "  ⚠ Uncommitted changes detected:"
        git status --short
        return 0
    else
        print_msg GREEN "  ✓ No uncommitted changes"
        return 1
    fi
}

#######################################
# Prompt for confirmation
# Arguments:
#   $1 - Message
# Returns: 0 if confirmed, 1 if cancelled
#######################################
confirm() {
    local msg="$1"

    if [ $FORCE_MODE -eq 1 ]; then
        return 0
    fi

    print_msg YELLOW "$msg"
    read -p "Continue? [y/N] " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

#######################################
# Release file reservations for agent
# Arguments:
#   $1 - Agent name
#######################################
release_agent_reservations() {
    local agent="$1"

    print_msg CYAN "  Releasing reservations for $agent..."

    # Release all reservations for this agent
    AGENT_NAME="$agent" ./scripts/reserve-files.sh release 2>/dev/null || true
}

#######################################
# Send shutdown notification
# Arguments:
#   $1 - Agent name
#   $2 - Session name
#######################################
send_shutdown_notification() {
    local agent="$1"
    local session="$2"

    if [ $SKIP_MAIL -eq 1 ]; then
        return 0
    fi

    print_msg CYAN "  Sending shutdown notification for $agent..."

    # Send mail notification
    AGENT_NAME="$agent" ./scripts/agent-mail-helper.sh send "Team" "swarm-$session" \
        "[$agent] Swarm shutdown initiated" \
        "Agent $agent in swarm '$session' is shutting down.

Shutdown initiated at $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Final status will be available in productivity summary.

This is an automated message from teardown-swarm.sh" 2>/dev/null || true
}

#######################################
# Generate productivity summary
# Arguments:
#   $1 - Session name
#   $2 - State JSON
# Outputs: Summary report
#######################################
generate_summary() {
    local session="$1"
    local state="$2"

    print_msg BLUE "Generating productivity summary..."

    # Extract metadata from state
    local spawn_time=$(echo "$state" | python3 -c "import sys,json; print(json.load(sys.stdin).get('spawn_time', 'unknown'))")
    local count=$(echo "$state" | python3 -c "import sys,json; print(json.load(sys.stdin).get('count', 0))")
    local agents=$(echo "$state" | python3 -c "import sys,json; data=json.load(sys.stdin); print(' '.join([a['name'] for a in data.get('agents', [])]))")

    local current_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Calculate duration
    local duration="unknown"
    if [ "$spawn_time" != "unknown" ] && command -v python3 &> /dev/null; then
        duration=$(python3 -c "
from datetime import datetime
try:
    start = datetime.fromisoformat('${spawn_time}'.replace('Z', '+00:00'))
    end = datetime.fromisoformat('${current_time}'.replace('Z', '+00:00'))
    delta = end - start
    hours = delta.seconds // 3600
    minutes = (delta.seconds % 3600) // 60
    print(f'{hours}h {minutes}m')
except:
    print('unknown')
" 2>/dev/null || echo "unknown")
    fi

    # Query task statistics
    local tasks_completed=0
    local tasks_in_progress=0

    if command -v br &> /dev/null; then
        for agent in $agents; do
            local agent_completed=$(br list --format json 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(len([t for t in data if t.get('owner') == '$agent' and t.get('status') == 'closed']))
except:
    print(0)
" 2>/dev/null || echo 0)

            local agent_in_progress=$(br list --format json 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(len([t for t in data if t.get('owner') == '$agent' and t.get('status') == 'open']))
except:
    print(0)
" 2>/dev/null || echo 0)

            tasks_completed=$((tasks_completed + agent_completed))
            tasks_in_progress=$((tasks_in_progress + agent_in_progress))
        done
    fi

    # Calculate productivity metrics
    local avg_task_time="N/A"
    if [ $tasks_completed -gt 0 ] && [ "$duration" != "unknown" ]; then
        # Rough estimate: divide total time by completed tasks
        avg_task_time=$(python3 -c "
try:
    duration_str = '${duration}'
    hours = int(duration_str.split('h')[0])
    minutes = int(duration_str.split('h')[1].split('m')[0])
    total_minutes = hours * 60 + minutes
    avg = total_minutes / ${tasks_completed}
    print(f'{int(avg)}m')
except:
    print('N/A')
" 2>/dev/null || echo "N/A")
    fi

    local efficiency="N/A"
    if [ $tasks_completed -gt 0 ]; then
        # Simple efficiency: completed / (completed + in_progress)
        efficiency=$(python3 -c "
try:
    completed = ${tasks_completed}
    total = ${tasks_completed} + ${tasks_in_progress}
    if total > 0:
        print(f'{int(completed * 100 / total)}%')
    else:
        print('N/A')
except:
    print('N/A')
" 2>/dev/null || echo "N/A")
    fi

    # Print summary
    cat <<EOF

================================================================
 Swarm Productivity Summary: $session
================================================================

Duration:           $spawn_time → $current_time ($duration)
Agent Count:        $count agents
Agents:             $agents

Task Statistics:
  Completed:        $tasks_completed tasks
  In Progress:      $tasks_in_progress tasks

Productivity Metrics:
  Efficiency:       $efficiency (completed / total)
  Avg Task Time:    $avg_task_time

================================================================
EOF

    # Option to save report
    if [ $FORCE_MODE -eq 0 ] && [ $REPORT_ONLY -eq 0 ]; then
        read -p "Save report to docs/sessions/swarm-${session}-summary.md? [y/N] " -n 1 -r
        echo

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            mkdir -p "$PROJECT_ROOT/docs/sessions"
            local report_file="$PROJECT_ROOT/docs/sessions/swarm-${session}-summary.md"

            cat > "$report_file" <<REPORT
# Swarm Session Summary: $session

**Duration:** $spawn_time → $current_time ($duration)
**Agent Count:** $count agents
**Agents:** $agents

## Task Statistics

- **Completed:** $tasks_completed tasks
- **In Progress:** $tasks_in_progress tasks

## Productivity Metrics

- **Efficiency:** $efficiency (completed / total)
- **Avg Task Time:** $avg_task_time

## Notes

_Summary generated by teardown-swarm.sh on $current_time_
REPORT

            print_msg GREEN "✓ Report saved to: $report_file"
        fi
    fi
}

#######################################
# Kill tmux session
# Arguments:
#   $1 - Session name
#######################################
kill_tmux_session() {
    local session="$1"

    if ! tmux has-session -t "$session" 2>/dev/null; then
        print_msg YELLOW "  ⚠ Tmux session '$session' not found (may already be closed)"
        return 0
    fi

    if [ $SHUTDOWN_DELAY -gt 0 ] && [ $FORCE_MODE -eq 0 ]; then
        print_msg YELLOW "  ⏳ Killing tmux session '$session' in ${SHUTDOWN_DELAY}s..."
        sleep $SHUTDOWN_DELAY
    fi

    print_msg CYAN "  Killing tmux session '$session'..."
    tmux kill-session -t "$session" 2>/dev/null || true

    print_msg GREEN "  ✓ Tmux session terminated"
}

#######################################
# Archive state file and clean up
# Arguments:
#   $1 - Session name
#######################################
archive_and_cleanup() {
    local session="$1"
    local state_file="$PIDS_DIR/swarm-${session}.state"

    print_msg CYAN "  Archiving state file..."

    # Create archive directory
    local archive_dir="$PIDS_DIR/archive"
    mkdir -p "$archive_dir"

    # Move state file to archive with timestamp
    local timestamp=$(date -u +"%Y%m%d-%H%M%S")
    local archive_file="$archive_dir/swarm-${session}-${timestamp}.state"

    if [ -f "$state_file" ]; then
        mv "$state_file" "$archive_file"
        print_msg GREEN "  ✓ State archived to: $archive_file"
    fi

    # Clean up agent name files
    print_msg CYAN "  Cleaning up agent name files..."
    rm -f "$PIDS_DIR"/swarm-${session}.agent-*.name

    print_msg GREEN "  ✓ Cleanup complete"
}

#######################################
# Main teardown process
# Arguments:
#   $1 - Session name
#######################################
teardown_swarm() {
    local session="$1"

    print_msg BLUE "========================================="
    print_msg BLUE "Swarm Teardown: $session"
    print_msg BLUE "========================================="

    # Read state file
    local state
    state=$(read_state_file "$session")

    # Extract agent names
    local agents=$(echo "$state" | python3 -c "import sys,json; data=json.load(sys.stdin); print(' '.join([a['name'] for a in data.get('agents', [])]))")

    # Pre-shutdown checks
    local has_tasks=0
    local has_reservations=0
    local has_uncommitted=0

    check_in_progress_tasks "$session" "$agents" && has_tasks=1 || has_tasks=0
    check_file_reservations "$agents" && has_reservations=1 || has_reservations=0
    check_uncommitted_work && has_uncommitted=1 || has_uncommitted=0

    # Warnings and confirmation
    if [ $has_tasks -eq 1 ] || [ $has_reservations -eq 1 ] || [ $has_uncommitted -eq 1 ]; then
        if ! confirm "⚠ Active work detected. Proceed with shutdown?"; then
            print_msg YELLOW "Shutdown cancelled by user"
            exit 3
        fi
    elif [ $FORCE_MODE -eq 0 ]; then
        if ! confirm "Proceed with swarm shutdown?"; then
            print_msg YELLOW "Shutdown cancelled by user"
            exit 3
        fi
    fi

    # Generate summary first (before cleanup)
    generate_summary "$session" "$state"

    if [ $REPORT_ONLY -eq 1 ]; then
        print_msg GREEN "Report generated. Skipping shutdown (--report mode)"
        exit 0
    fi

    # Shutdown sequence
    print_msg BLUE ""
    print_msg BLUE "Beginning shutdown sequence..."

    # Release reservations for each agent
    for agent in $agents; do
        release_agent_reservations "$agent"
    done

    # Send notifications for each agent
    for agent in $agents; do
        send_shutdown_notification "$agent" "$session"
    done

    # Kill tmux session
    kill_tmux_session "$session"

    # Archive and cleanup
    archive_and_cleanup "$session"

    print_msg GREEN ""
    print_msg GREEN "========================================="
    print_msg GREEN "Swarm '$session' successfully torn down"
    print_msg GREEN "========================================="
}

#######################################
# Main script
#######################################
main() {
    # Parse arguments
    if [ $# -eq 0 ]; then
        usage
        exit 1
    fi

    local session=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --help)
                usage
                exit 0
                ;;
            --force)
                FORCE_MODE=1
                shift
                ;;
            --report)
                REPORT_ONLY=1
                shift
                ;;
            --skip-mail)
                SKIP_MAIL=1
                shift
                ;;
            --delay)
                SHUTDOWN_DELAY="$2"
                shift 2
                ;;
            *)
                if [ -z "$session" ]; then
                    session="$1"
                else
                    print_msg RED "Error: Unknown argument: $1"
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done

    if [ -z "$session" ]; then
        print_msg RED "Error: Missing required argument: swarm-session"
        usage
        exit 1
    fi

    teardown_swarm "$session"
}

main "$@"
