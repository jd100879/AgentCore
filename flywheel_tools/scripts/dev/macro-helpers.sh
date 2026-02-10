#!/usr/bin/env bash
# Macro Helper Script
# Wraps upstream MCP macro tools for easy shell access

# Source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/project-config.sh"

# Mail server configuration
MAIL_SERVER="${MAIL_SERVER:-http://127.0.0.1:8765}"
MCP_AGENT_MAIL_DIR="${MCP_AGENT_MAIL_DIR:-$HOME/mcp_agent_mail}"
TOKEN_FILE="$MCP_AGENT_MAIL_DIR/.env"

# Load token
if [ ! -f "$TOKEN_FILE" ]; then
    echo "Error: Token file not found at $TOKEN_FILE" >&2
    exit 1
fi
TOKEN=$(grep HTTP_BEARER_TOKEN "$TOKEN_FILE" | cut -d'=' -f2)

# Function to make MCP API calls
mcp_call() {
    local method=$1
    local params=$2

    curl -s -X POST "$MAIL_SERVER/mcp" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\"$method\",\"arguments\":$params},\"id\":$(date +%s)}"
}

# Get current agent name
whoami_agent() {
    if [ -n "$TMUX_PANE" ]; then
        PANE_ID=$(tmux display-message -t "$TMUX_PANE" -p "#{session_name}:#{window_index}.#{pane_index}" 2>/dev/null)
    else
        PANE_ID=$(tmux display-message -p "#{session_name}:#{window_index}.#{pane_index}" 2>/dev/null)
    fi

    if [ -z "$PANE_ID" ]; then
        echo "Error: Not in tmux session" >&2
        return 1
    fi

    SAFE_PANE=$(echo "$PANE_ID" | tr ':.' '-')
    AGENT_NAME_FILE="$PROJECT_ROOT/pids/${SAFE_PANE}.agent-name"

    if [ -f "$AGENT_NAME_FILE" ]; then
        cat "$AGENT_NAME_FILE"
    else
        echo "Error: Agent name file not found: $AGENT_NAME_FILE" >&2
        return 1
    fi
}

# Macro 1: Start Session
# Initializes project environment, agent identity, file reservations, and inbox
macro_start_session() {
    local project_key="${1:-$(basename "$PROJECT_ROOT")}"
    local agent_name="${2:-$(whoami_agent)}"
    local task_description="${3:-Starting new work session}"

    if [ -z "$agent_name" ]; then
        echo "Error: Could not determine agent name" >&2
        return 1
    fi

    echo "Starting session for $agent_name in project $project_key..." >&2

    local params=$(jq -n \
        --arg human_key "$project_key" \
        --arg agent_name "$agent_name" \
        --arg program "claude-code" \
        --arg model "sonnet" \
        --arg task_desc "$task_description" \
        '{
            human_key: $human_key,
            agent_name: $agent_name,
            program: $program,
            model: $model,
            task_description: $task_desc
        }')

    local response=$(mcp_call "macro_start_session" "$params")

    # Check for errors
    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        echo "Error calling macro_start_session:" >&2
        echo "$response" | jq -r '.error.message // .error' >&2
        return 1
    fi

    # Display structured content if available
    if echo "$response" | jq -e '.result.structuredContent.result' >/dev/null 2>&1; then
        echo "$response" | jq -r '.result.structuredContent.result'
    else
        echo "$response" | jq -r '.result.content[0].text // .result // .'
    fi
}

# Macro 2: File Reservation Cycle
# Manages complete reserve → work → release workflow
macro_file_reservation_cycle() {
    local action="${1:-status}"  # reserve, work, release, status
    local file_patterns="${2:-}"
    local task_id="${3:-}"
    local agent_name="${4:-$(whoami_agent)}"

    if [ -z "$agent_name" ]; then
        echo "Error: Could not determine agent name" >&2
        return 1
    fi

    case "$action" in
        reserve)
            if [ -z "$file_patterns" ] || [ -z "$task_id" ]; then
                echo "Usage: macro_file_reservation_cycle reserve 'file/patterns' 'task-id'" >&2
                return 1
            fi
            echo "Reserving files for $task_id..." >&2
            ;;
        work)
            echo "Marking reservation as active work..." >&2
            ;;
        release)
            echo "Releasing file reservations..." >&2
            ;;
        status)
            echo "Checking reservation status..." >&2
            ;;
        *)
            echo "Error: Unknown action '$action'. Use: reserve, work, release, or status" >&2
            return 1
            ;;
    esac

    local params=$(jq -n \
        --arg action "$action" \
        --arg agent_name "$agent_name" \
        --arg file_patterns "$file_patterns" \
        --arg task_id "$task_id" \
        '{
            action: $action,
            agent_name: $agent_name,
            file_patterns: $file_patterns,
            task_id: $task_id
        }')

    local response=$(mcp_call "macro_file_reservation_cycle" "$params")

    # Check for errors
    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        echo "Error calling macro_file_reservation_cycle:" >&2
        echo "$response" | jq -r '.error.message // .error' >&2
        return 1
    fi

    # Display result
    if echo "$response" | jq -e '.result.structuredContent.result' >/dev/null 2>&1; then
        echo "$response" | jq -r '.result.structuredContent.result'
    else
        echo "$response" | jq -r '.result.content[0].text // .result // .'
    fi
}

# Macro 3: Complete Task
# Handles task completion with context documentation
macro_complete_task() {
    local task_id="$1"
    local summary="${2:-Task completed}"
    local deliverables="${3:-}"
    local agent_name="${4:-$(whoami_agent)}"

    if [ -z "$task_id" ]; then
        echo "Usage: macro_complete_task <task-id> [summary] [deliverables]" >&2
        return 1
    fi

    if [ -z "$agent_name" ]; then
        echo "Error: Could not determine agent name" >&2
        return 1
    fi

    echo "Completing task $task_id..." >&2

    local params=$(jq -n \
        --arg task_id "$task_id" \
        --arg agent_name "$agent_name" \
        --arg summary "$summary" \
        --arg deliverables "$deliverables" \
        '{
            task_id: $task_id,
            agent_name: $agent_name,
            summary: $summary,
            deliverables: $deliverables
        }')

    local response=$(mcp_call "macro_complete_task" "$params")

    # Check for errors
    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        echo "Error calling macro_complete_task:" >&2
        echo "$response" | jq -r '.error.message // .error' >&2
        return 1
    fi

    # Display result
    if echo "$response" | jq -e '.result.structuredContent.result' >/dev/null 2>&1; then
        echo "$response" | jq -r '.result.structuredContent.result'
    else
        echo "$response" | jq -r '.result.content[0].text // .result // .'
    fi
}

# Usage help
show_usage() {
    cat << 'EOF'
Macro Helper Script - Wrappers for upstream MCP macro tools

Usage:
  source ./scripts/macro-helpers.sh

Functions:
  macro_start_session [project] [agent] [task_description]
    Initialize session with project context, agent identity, and inbox

  macro_file_reservation_cycle <action> [file_patterns] [task_id] [agent]
    Manage file reservation lifecycle: reserve, work, release, status

  macro_complete_task <task_id> [summary] [deliverables] [agent]
    Complete task with context documentation

Examples:
  # Start session
  macro_start_session "my-project" "DarkGlen" "Working on authentication"

  # Reserve files
  macro_file_reservation_cycle reserve "src/**/*.py" "bd-123" "DarkGlen"

  # Check reservation status
  macro_file_reservation_cycle status

  # Release reservations
  macro_file_reservation_cycle release

  # Complete task
  macro_complete_task "bd-123" "Auth implemented" "src/auth.py,tests/test_auth.py"

For more information, see AGENT_MAIL.md
EOF
}

# If sourced, export functions; if executed, show usage
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    show_usage
fi
