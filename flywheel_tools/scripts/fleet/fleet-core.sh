#!/usr/bin/env bash
# Fleet Dashboard - Core Data Aggregator
# Collects and caches multi-agent fleet status data
#
# Usage:
#   ./scripts/fleet-core.sh aggregate           # Full aggregated status (JSON)
#   ./scripts/fleet-core.sh get_active_agents   # Only agents (JSON)
#   ./scripts/fleet-core.sh get_task_status     # Only tasks (JSON)
#   ./scripts/fleet-core.sh get_reservations    # Only reservations (JSON)
#   ./scripts/fleet-core.sh get_mail_status     # Only mail (JSON)
#   ./scripts/fleet-core.sh get_system_health   # Only health (JSON)
#   ./scripts/fleet-core.sh cache_clear         # Clear all caches

set -uo pipefail

# Source shared project configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/project-config.sh"

# Cache configuration
CACHE_DIR="/tmp/fleet-cache"
mkdir -p "$CACHE_DIR"

# Cache TTLs (seconds)
TTL_TMUX=1
TTL_AGENTS=5
TTL_TASKS=10
TTL_RESERVATIONS=5
TTL_MAIL=30
TTL_HEALTH=10

# Color codes for output (optional, for future CLI use)
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# CACHING FUNCTIONS
# ============================================================================

# Check if cache file is fresh (within TTL)
# Args: $1=cache_file, $2=ttl_seconds
# Returns: 0 if fresh, 1 if stale/missing
cache_is_fresh() {
    local cache_file="$1"
    local ttl="$2"

    if [ ! -f "$cache_file" ]; then
        return 1
    fi

    local file_age=$(( $(date +%s) - $(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo 0) ))

    if [ "$file_age" -lt "$ttl" ]; then
        return 0
    else
        return 1
    fi
}

# Get cached data if fresh, otherwise return empty
# Args: $1=cache_key, $2=ttl_seconds
# Output: JSON data or empty string
cache_get() {
    local key="$1"
    local ttl="$2"
    local cache_file="$CACHE_DIR/${key}.json"

    if cache_is_fresh "$cache_file" "$ttl"; then
        cat "$cache_file"
    else
        echo ""
    fi
}

# Set cache data
# Args: $1=cache_key, stdin=JSON data
cache_set() {
    local key="$1"
    local cache_file="$CACHE_DIR/${key}.json"
    cat > "$cache_file"
}

# Clear all cache files
cache_clear() {
    rm -f "$CACHE_DIR"/*.json
    echo '{"status": "success", "message": "Cache cleared"}' | jq .
}

# Cleanup stale cache files (older than 1 hour)
cache_cleanup() {
    local max_age=3600  # 1 hour in seconds
    local now=$(date +%s)
    local removed=0

    for cache_file in "$CACHE_DIR"/*.json; do
        if [ -f "$cache_file" ]; then
            local file_age=$(( now - $(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo 0) ))
            if [ "$file_age" -gt "$max_age" ]; then
                rm -f "$cache_file"
                ((removed++))
            fi
        fi
    done

    echo "{\"status\": \"success\", \"message\": \"Cleaned up $removed stale cache files\"}" | jq .
}

# ============================================================================
# DATA COLLECTION FUNCTIONS
# ============================================================================

# Get active agents from tmux panes and agent-name files
# Output: JSON array of agent objects
get_active_agents() {
    # Check cache first
    local cached=$(cache_get "agents" "$TTL_AGENTS")
    if [ -n "$cached" ]; then
        echo "$cached"
        return 0
    fi

    # Collect fresh data
    local agents_json="[]"

    # Check if tmux is available
    if ! command -v tmux &> /dev/null; then
        echo '{"error": "tmux not available", "agents": []}' | tee >(cache_set "agents")
        return 1
    fi

    # Get all tmux panes
    local panes=$(tmux list-panes -a -F "#{session_name}:#{window_index}.#{pane_index}|#{pane_current_command}|#{pane_current_path}" 2>/dev/null || echo "")

    if [ -z "$panes" ]; then
        echo '{"count": 0, "active": 0, "idle": 0, "agents": []}' | tee >(cache_set "agents")
        return 0
    fi

    local active_count=0
    local idle_count=0
    local agent_objects=()

    while IFS='|' read -r pane_id command path; do
        # Convert pane ID to safe filename format (e.g., "session555:1.2" -> "session555-1-2")
        local safe_pane=$(echo "$pane_id" | tr ':.' '-')
        local agent_name_file="$PIDS_DIR/${safe_pane}.agent-name"

        local agent_name="unknown"
        local status="idle"
        local current_task=""

        # Read agent name if file exists
        if [ -f "$agent_name_file" ]; then
            agent_name=$(cat "$agent_name_file" 2>/dev/null || echo "unknown")
        fi

        # Determine status based on command
        if [[ "$command" == "claude" ]]; then
            status="active"
            ((active_count++))

            # Correlate with Beads tasks - find task assigned to this agent
            if command -v br &> /dev/null && [ "$agent_name" != "unknown" ]; then
                # Query for tasks assigned to this agent that are in progress
                local assigned_task=$(br list --status in_progress --json 2>/dev/null | \
                    jq -r --arg agent "$agent_name" '.[] | select(.assignee == $agent) | .id' | \
                    head -n 1 || echo "")

                if [ -n "$assigned_task" ]; then
                    current_task="$assigned_task"
                fi
            fi
        else
            status="idle"
            ((idle_count++))
        fi

        # Build agent object
        local agent_obj=$(jq -n \
            --arg name "$agent_name" \
            --arg pane "$pane_id" \
            --arg cmd "$command" \
            --arg status "$status" \
            --arg task "$current_task" \
            --arg path "$path" \
            '{
                name: $name,
                pane: $pane,
                command: $cmd,
                status: $status,
                current_task: $task,
                path: $path
            }')

        agent_objects+=("$agent_obj")
    done <<< "$panes"

    # Combine into final JSON
    local total_count=${#agent_objects[@]}

    # Build agents array
    local agents_array="[]"
    for obj in "${agent_objects[@]}"; do
        agents_array=$(echo "$agents_array" | jq --argjson agent "$obj" '. += [$agent]')
    done

    # Build final result
    local result=$(jq -n \
        --argjson count "$total_count" \
        --argjson active "$active_count" \
        --argjson idle "$idle_count" \
        --argjson agents "$agents_array" \
        '{
            count: $count,
            active: $active,
            idle: $idle,
            agents: $agents
        }')

    # Cache and output
    echo "$result" | tee >(cache_set "agents")
}

# Get task status from Beads
# Output: JSON object with task counts and details
get_task_status() {
    # Check cache first
    local cached=$(cache_get "tasks" "$TTL_TASKS")
    if [ -n "$cached" ]; then
        echo "$cached"
        return 0
    fi

    # Check if br command exists
    if ! command -v br &> /dev/null; then
        echo '{"error": "br command not available", "ready": 0, "in_progress": 0, "blocked": 0, "completed_today": 0, "tasks": []}' | tee >(cache_set "tasks")
        return 1
    fi

    # Get task lists
    local ready_tasks=$(br list --status ready --json 2>/dev/null || echo "[]")
    local in_progress_tasks=$(br list --status open --json 2>/dev/null || echo "[]")
    local blocked_tasks=$(br list --status blocked --json 2>/dev/null || echo "[]")

    # Count tasks
    local ready_count=$(echo "$ready_tasks" | jq 'length')
    local in_progress_count=$(echo "$in_progress_tasks" | jq 'length')
    local blocked_count=$(echo "$blocked_tasks" | jq 'length')

    # Get completed tasks from today
    local today=$(date -u +"%Y-%m-%d")
    local completed_today_tasks=$(br search --status closed --all "." --format json --limit 1000 2>/dev/null | \
        jq --arg today "$today" '[.[] | select(.closed_at != null and (.closed_at | startswith($today)))]' || echo "[]")
    local completed_today=$(echo "$completed_today_tasks" | jq 'length')

    # Build result
    local result=$(jq -n \
        --argjson ready "$ready_count" \
        --argjson in_progress "$in_progress_count" \
        --argjson blocked "$blocked_count" \
        --argjson completed "$completed_today" \
        --argjson ready_list "$ready_tasks" \
        --argjson in_progress_list "$in_progress_tasks" \
        --argjson blocked_list "$blocked_tasks" \
        '{
            ready: $ready,
            in_progress: $in_progress,
            blocked: $blocked,
            completed_today: $completed,
            tasks: {
                ready: $ready_list,
                in_progress: $in_progress_list,
                blocked: $blocked_list
            }
        }')

    # Cache and output
    echo "$result" | tee >(cache_set "tasks")
}

# Get file reservations
# Output: JSON array of reservation objects
get_reservations() {
    # Check cache first
    local cached=$(cache_get "reservations" "$TTL_RESERVATIONS")
    if [ -n "$cached" ]; then
        echo "$cached"
        return 0
    fi

    # Check if reserve-files.sh exists
    if [ ! -f "$SCRIPT_DIR/reserve-files.sh" ]; then
        echo '{"error": "reserve-files.sh not found", "count": 0, "expiring_soon": 0, "reservations": []}' | tee >(cache_set "reservations")
        return 1
    fi

    # Get all reservations
    local raw_output=$("$SCRIPT_DIR/reserve-files.sh" list-all 2>/dev/null || echo "")

    if [ -z "$raw_output" ]; then
        echo '{"count": 0, "expiring_soon": 0, "reservations": []}' | tee >(cache_set "reservations")
        return 0
    fi

    # Parse reservations (simple text parsing for now)
    # Format: [AgentName] path/to/file (ID: 123, exclusive: true, expires: 2026-01-31T12:00:00Z)

    local reservations_array="[]"
    local total_count=0
    local expiring_soon=0

    while IFS= read -r line; do
        # Skip header lines
        if [[ "$line" == *"active reservations"* ]] || [[ "$line" == "====" ]]; then
            continue
        fi

        # Parse line (this is a simplified parser - TODO: make more robust)
        if [[ "$line" =~ \[([^]]+)\]\ ([^(]+).*expires:\ ([^)]+) ]]; then
            local agent="${BASH_REMATCH[1]}"
            local file_path="${BASH_REMATCH[2]}"
            local expires="${BASH_REMATCH[3]}"

            # Trim whitespace
            agent=$(echo "$agent" | xargs)
            file_path=$(echo "$file_path" | xargs)
            expires=$(echo "$expires" | xargs)

            # Calculate time until expiration
            local time_remaining="unknown"
            local expiring_soon=false

            # Parse ISO 8601 timestamp and calculate remaining time
            if command -v date &> /dev/null; then
                local expires_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$expires" "+%s" 2>/dev/null || echo "0")
                local now_epoch=$(date +%s)

                if [ "$expires_epoch" -gt 0 ]; then
                    local seconds_remaining=$((expires_epoch - now_epoch))

                    if [ "$seconds_remaining" -lt 0 ]; then
                        time_remaining="EXPIRED"
                        expiring_soon=true
                    elif [ "$seconds_remaining" -lt 1800 ]; then
                        # Less than 30 minutes
                        local minutes=$((seconds_remaining / 60))
                        time_remaining="${minutes}m"
                        expiring_soon=true
                        ((expiring_soon++))
                    elif [ "$seconds_remaining" -lt 7200 ]; then
                        # Less than 2 hours
                        local minutes=$((seconds_remaining / 60))
                        time_remaining="${minutes}m"
                    else
                        # More than 2 hours
                        local hours=$((seconds_remaining / 3600))
                        local minutes=$(( (seconds_remaining % 3600) / 60 ))
                        time_remaining="${hours}h${minutes}m"
                    fi
                fi
            fi

            local res_obj=$(jq -n \
                --arg agent "$agent" \
                --arg path "$file_path" \
                --arg expires "$expires" \
                --arg remaining "$time_remaining" \
                --argjson expiring "$expiring_soon" \
                '{
                    agent: $agent,
                    path: $path,
                    expires: $expires,
                    time_remaining: $remaining,
                    expiring_soon: $expiring
                }')

            reservations_array=$(echo "$reservations_array" | jq --argjson res "$res_obj" '. += [$res]')
            ((total_count++))
        fi
    done <<< "$raw_output"

    # Build result
    local result=$(jq -n \
        --argjson count "$total_count" \
        --argjson expiring "$expiring_soon" \
        --argjson reservations "$reservations_array" \
        '{
            count: $count,
            expiring_soon: $expiring,
            reservations: $reservations
        }')

    # Cache and output
    echo "$result" | tee >(cache_set "reservations")
}

# Get agent mail status
# Output: JSON object with unread counts and recent messages
get_mail_status() {
    # Check cache first
    local cached=$(cache_get "mail" "$TTL_MAIL")
    if [ -n "$cached" ]; then
        echo "$cached"
        return 0
    fi

    # Check if agent-mail-helper.sh exists
    if [ ! -f "$SCRIPT_DIR/agent-mail-helper.sh" ]; then
        echo '{"error": "agent-mail-helper.sh not found", "total_unread": 0, "agents": []}' | tee >(cache_set "mail")
        return 1
    fi

    # Get list of project agents from agent-name files
    local -a project_agents=()
    if [ -d "$PIDS_DIR" ]; then
        while IFS= read -r agent_file; do
            if [ -f "$agent_file" ]; then
                local agent_name=$(cat "$agent_file" 2>/dev/null || echo "")
                if [ -n "$agent_name" ]; then
                    # Check if agent already in array (simple approach for bash 4+)
                    local already_added=false
                    for existing in "${project_agents[@]+"${project_agents[@]}"}"; do
                        if [ "$existing" = "$agent_name" ]; then
                            already_added=true
                            break
                        fi
                    done
                    if [ "$already_added" = false ]; then
                        project_agents+=("$agent_name")
                    fi
                fi
            fi
        done < <(find "$PIDS_DIR" -name "*.agent-name" 2>/dev/null)
    fi

    # If no agents found, return empty structure
    local agent_count="${#project_agents[@]}"
    if [ "$agent_count" -eq 0 ]; then
        echo '{"total_unread": 0, "agents": [], "recent_messages": []}' | tee >(cache_set "mail")
        return 0
    fi

    # Mail server config (same as agent-mail-helper.sh)
    local mail_server="${MAIL_SERVER:-http://127.0.0.1:8765}"
    local mcp_dir="${MCP_AGENT_MAIL_DIR:-$HOME/mcp_agent_mail}"
    local token_file="$mcp_dir/.env"
    local read_receipts="$PROJECT_ROOT/.beads/mail-read.jsonl"

    if [ ! -f "$token_file" ]; then
        echo '{"error": "mail token not found", "total_unread": 0, "agents": []}' | tee >(cache_set "mail")
        return 1
    fi
    local token=$(grep HTTP_BEARER_TOKEN "$token_file" | cut -d'=' -f2)

    local agent_mail_status="[]"
    local total_unread=0

    for agent in "${project_agents[@]}"; do
        # Fetch inbox for this agent via MCP API
        local inbox_response=$(curl -s --max-time 5 -X POST "$mail_server/mcp" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -d "{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\"fetch_inbox\",\"arguments\":{\"project_key\":\"$MAIL_PROJECT_KEY\",\"agent_name\":\"$agent\",\"limit\":50,\"include_bodies\":false}},\"id\":$(date +%s)}" 2>/dev/null || echo '{}')

        local msg_count=$(echo "$inbox_response" | jq -r '.result.structuredContent.result | length // 0' 2>/dev/null || echo 0)
        local unread=0

        # Count unread by checking each message against read receipts
        if [ "$msg_count" -gt 0 ] && [ -f "$read_receipts" ] && [ -s "$read_receipts" ]; then
            while IFS= read -r msg; do
                local from=$(echo "$msg" | jq -r '.from // empty')
                local subject=$(echo "$msg" | jq -r '.subject // empty' | tr -d '\n')
                if [ -n "$from" ] && [ -n "$subject" ]; then
                    local msg_hash=$(printf "%s" "${from}::${subject}" | md5 2>/dev/null || printf "%s" "${from}::${subject}" | md5sum 2>/dev/null | cut -d' ' -f1)
                    if ! jq -e --arg agent "$agent" --arg hash "$msg_hash" \
                        'select(.agent == $agent and .message_hash == $hash)' \
                        "$read_receipts" >/dev/null 2>&1; then
                        unread=$((unread + 1))
                    fi
                fi
            done < <(echo "$inbox_response" | jq -c '.result.structuredContent.result[]' 2>/dev/null)
        elif [ "$msg_count" -gt 0 ]; then
            # No read receipts file — all messages are unread
            unread=$msg_count
        fi

        total_unread=$((total_unread + unread))
        local agent_obj=$(jq -n \
            --arg name "$agent" \
            --argjson unread "$unread" \
            --argjson total "$msg_count" \
            '{name: $name, unread: $unread, total: $total}')
        agent_mail_status=$(echo "$agent_mail_status" | jq --argjson agent "$agent_obj" '. += [$agent]')
    done

    # Build result
    local result=$(jq -n \
        --argjson total "$total_unread" \
        --argjson agents "$agent_mail_status" \
        '{
            total_unread: $total,
            agents: $agents,
            recent_messages: []
        }')

    # Cache and output
    echo "$result" | tee >(cache_set "mail")
}

# Get system health status
# Output: JSON object with health checks
get_system_health() {
    # Check cache first
    local cached=$(cache_get "health" "$TTL_HEALTH")
    if [ -n "$cached" ]; then
        echo "$cached"
        return 0
    fi

    local health_checks=()

    # Check 1: Mail monitor status
    local mail_monitor_status="unknown"
    if [ -f "$SCRIPT_DIR/mail-monitor-ctl.sh" ]; then
        if "$SCRIPT_DIR/mail-monitor-ctl.sh" status &>/dev/null; then
            mail_monitor_status="running"
        else
            mail_monitor_status="stopped"
        fi
    fi

    # Check 2: Hook bypass status
    local hook_bypass="disabled"
    if [ -f "$SCRIPT_DIR/hook-bypass.sh" ]; then
        local bypass_output=$("$SCRIPT_DIR/hook-bypass.sh" status 2>/dev/null || echo "")
        if echo "$bypass_output" | grep -q "ENABLED"; then
            hook_bypass="enabled"
        fi
    fi

    # Check 3: MCP Agent Mail server
    local mcp_mail_status="unknown"
    if nc -z localhost 8765 &>/dev/null; then
        mcp_mail_status="up"
    else
        mcp_mail_status="down"
    fi

    # Check 4: Beads server
    local beads_status="unknown"
    if br list --json &>/dev/null; then
        beads_status="up"
    else
        beads_status="down"
    fi

    # Determine overall health
    local overall_healthy=true
    if [[ "$mcp_mail_status" == "down" ]] || [[ "$beads_status" == "down" ]]; then
        overall_healthy=false
    fi

    # Build result
    local result=$(jq -n \
        --argjson healthy "$overall_healthy" \
        --arg mail_monitor "$mail_monitor_status" \
        --arg hook_bypass "$hook_bypass" \
        --arg mcp_mail "$mcp_mail_status" \
        --arg beads "$beads_status" \
        '{
            healthy: $healthy,
            checks: {
                mail_monitor: $mail_monitor,
                hook_bypass: $hook_bypass,
                mcp_agent_mail: $mcp_mail,
                beads_server: $beads
            }
        }')

    # Cache and output
    echo "$result" | tee >(cache_set "health")
}

# ============================================================================
# TASK ASSIGNMENT RECOMMENDATIONS
# ============================================================================

# Get task assignment recommendations based on agent history
# Analyzes completed tasks to suggest best agent for ready tasks
# Output: JSON with recommendations for each ready task
get_task_recommendations() {
    # Get ready tasks (open, unblocked)
    local ready_tasks=$(br ready --json 2>/dev/null || echo '[]')

    # Get recently closed tasks (last 50) with agent and labels
    local closed_tasks=$(br search --status closed --all "." --format json --limit 50 2>/dev/null || echo '[]')

    # Build recommendations
    local recommendations='[]'

    # Process each ready task
    for task_id in $(echo "$ready_tasks" | jq -r '.[].id // empty'); do
        local task_labels=$(echo "$ready_tasks" | jq -r --arg id "$task_id" '.[] | select(.id == $id) | .labels[]? // empty')

        if [[ -z "$task_labels" ]]; then
            # No labels, skip recommendation
            continue
        fi

        # Count matches per agent across closed tasks
        declare -A agent_scores

        while IFS= read -r label; do
            # Find agents who completed tasks with this label
            local matching_agents=$(echo "$closed_tasks" | jq -r --arg label "$label" \
                '.[] | select(.labels[]? == $label) | .owner // empty' | sort | uniq)

            while IFS= read -r agent; do
                if [[ -n "$agent" ]]; then
                    agent_scores[$agent]=$((${agent_scores[$agent]:-0} + 1))
                fi
            done <<< "$matching_agents"
        done <<< "$task_labels"

        # Find agent with highest score
        local best_agent=""
        local best_score=0
        for agent in "${!agent_scores[@]}"; do
            if (( ${agent_scores[$agent]} > best_score )); then
                best_score=${agent_scores[$agent]}
                best_agent="$agent"
            fi
        done

        # Add recommendation if found
        if [[ -n "$best_agent" ]]; then
            local rec=$(jq -n \
                --arg task_id "$task_id" \
                --arg agent "$best_agent" \
                --argjson score "$best_score" \
                '{task_id: $task_id, recommended_agent: $agent, confidence: $score}')
            recommendations=$(echo "$recommendations" | jq --argjson rec "$rec" '. + [$rec]')
        fi

        # Clear associative array for next task
        unset agent_scores
    done

    # Output results
    echo "$recommendations"
}

# ============================================================================
# AGGREGATION FUNCTION
# ============================================================================

# Aggregate all data sources into single JSON object
# Output: Complete fleet status JSON
aggregate() {
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Collect all data (uses caching internally)
    local agents=$(get_active_agents 2>/dev/null || echo '{"error": "failed", "agents": []}')
    local tasks=$(get_task_status 2>/dev/null || echo '{"error": "failed"}')
    local reservations=$(get_reservations 2>/dev/null || echo '{"error": "failed", "reservations": []}')
    local mail=$(get_mail_status 2>/dev/null || echo '{"error": "failed"}')
    local health=$(get_system_health 2>/dev/null || echo '{"error": "failed"}')

    # Build aggregate result
    jq -n \
        --arg timestamp "$timestamp" \
        --argjson agents "$agents" \
        --argjson tasks "$tasks" \
        --argjson reservations "$reservations" \
        --argjson mail "$mail" \
        --argjson health "$health" \
        '{
            timestamp: $timestamp,
            agents: $agents,
            tasks: $tasks,
            reservations: $reservations,
            mail: $mail,
            health: $health
        }'
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

main() {
    local command="${1:-aggregate}"

    case "$command" in
        aggregate)
            aggregate
            ;;
        get_active_agents)
            get_active_agents
            ;;
        get_task_status)
            get_task_status
            ;;
        get_reservations)
            get_reservations
            ;;
        get_mail_status)
            get_mail_status
            ;;
        get_system_health)
            get_system_health
            ;;
        get_task_recommendations)
            get_task_recommendations
            ;;
        cache_clear)
            cache_clear
            ;;
        cache_cleanup)
            cache_cleanup
            ;;
        *)
            echo "Usage: $0 {aggregate|get_active_agents|get_task_status|get_reservations|get_mail_status|get_system_health|get_task_recommendations|cache_clear|cache_cleanup}" >&2
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
