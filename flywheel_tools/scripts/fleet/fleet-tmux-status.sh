#!/usr/bin/env bash
#
# fleet-tmux-status.sh - Compact one-line fleet status for tmux status bar
#
# Usage:
#   Add to .tmux.conf:
#     set -g status-right "#(~/path/to/scripts/fleet-tmux-status.sh)"
#     set -g status-interval 5
#
# Output format:
#   [Fleet: 3A 12R 4P | Files: 5L(3⚠) | Mail: 3U | ✓]
#
# Legend:
#   3A = active agents
#   12R = ready tasks
#   4P = in-progress tasks
#   5L = locked files
#   3⚠ = expiring soon
#   3U = unread mail
#   ✓/✗ = health status

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/project-config.sh"

# Tmux color codes
# Format: #[fg=color,bg=color]text#[default]
if [[ -n "${TMUX:-}" ]]; then
    COLOR_GREEN="#[fg=green]"
    COLOR_YELLOW="#[fg=yellow]"
    COLOR_RED="#[fg=red]"
    COLOR_BLUE="#[fg=blue]"
    COLOR_GRAY="#[fg=brightblack]"
    COLOR_RESET="#[default]"
else
    # ANSI fallback for testing outside tmux
    COLOR_GREEN='\033[0;32m'
    COLOR_YELLOW='\033[0;33m'
    COLOR_RED='\033[0;31m'
    COLOR_BLUE='\033[0;34m'
    COLOR_GRAY='\033[0;90m'
    COLOR_RESET='\033[0m'
fi

# Get fleet data from cache (fast path)
CACHE_FILE="$PROJECT_ROOT/.cache/fleet-status.json"
CACHE_MAX_AGE=10  # seconds

get_fleet_data() {
    # Try cache first for <100ms response
    if [[ -f "$CACHE_FILE" ]]; then
        local cache_age=$(($(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)))
        if [[ $cache_age -lt $CACHE_MAX_AGE ]]; then
            cat "$CACHE_FILE"
            return 0
        fi
    fi

    # Fallback: generate fresh data
    "$SCRIPT_DIR/fleet-core.sh" 2>/dev/null || echo "{}"
}

# Parse JSON data
data=$(get_fleet_data)

# Extract metrics using jq (fast path - single jq call)
metrics=$(echo "$data" | jq -r '
    .agents.active // 0,
    .agents.total // 0,
    .tasks.ready // 0,
    .tasks.in_progress // 0,
    .file_reservations.locked_count // 0,
    .file_reservations.expiring_soon // 0,
    .mail.unread_count // 0,
    .health.status // "unknown"
' 2>/dev/null)

# Read metrics into variables
read -r agents_active agents_total tasks_ready tasks_progress files_locked files_expiring mail_unread health_status <<< "$(echo "$metrics" | tr '\n' ' ')"

# Default to 0 if parsing failed
agents_active=${agents_active:-0}
agents_total=${agents_total:-0}
tasks_ready=${tasks_ready:-0}
tasks_progress=${tasks_progress:-0}
files_locked=${files_locked:-0}
files_expiring=${files_expiring:-0}
mail_unread=${mail_unread:-0}
health_status=${health_status:-unknown}

# Color-code based on health and values
agent_color="$COLOR_GREEN"
if [[ $agents_active -eq 0 ]]; then
    agent_color="$COLOR_GRAY"
elif [[ $agents_active -lt $(( agents_total / 2 )) ]]; then
    agent_color="$COLOR_YELLOW"
fi

task_color="$COLOR_GREEN"
if [[ $tasks_ready -eq 0 ]]; then
    task_color="$COLOR_GRAY"
fi

file_color="$COLOR_GREEN"
if [[ $files_expiring -gt 0 ]]; then
    file_color="$COLOR_YELLOW"
fi
if [[ $files_locked -gt 5 ]]; then
    file_color="$COLOR_YELLOW"
fi

mail_color="$COLOR_BLUE"
if [[ $mail_unread -gt 5 ]]; then
    mail_color="$COLOR_YELLOW"
fi

health_color="$COLOR_GREEN"
health_icon="✓"
case "$health_status" in
    healthy)
        health_color="$COLOR_GREEN"
        health_icon="✓"
        ;;
    degraded)
        health_color="$COLOR_YELLOW"
        health_icon="⚠"
        ;;
    unhealthy)
        health_color="$COLOR_RED"
        health_icon="✗"
        ;;
    *)
        health_color="$COLOR_GRAY"
        health_icon="?"
        ;;
esac

# Build compact status line
# Format: [Fleet: 3A 12R 4P | Files: 5L(3⚠) | Mail: 3U | ✓]
status=""
status+="${COLOR_GRAY}[Fleet: "
status+="${agent_color}${agents_active}A${COLOR_RESET} "
status+="${task_color}${tasks_ready}R${COLOR_RESET} "
status+="${COLOR_GRAY}${tasks_progress}P${COLOR_RESET} "
status+="${COLOR_GRAY}| Files: "
status+="${file_color}${files_locked}L"

if [[ $files_expiring -gt 0 ]]; then
    status+="${COLOR_YELLOW}(${files_expiring}⚠)${COLOR_RESET}"
fi

status+="${COLOR_RESET} ${COLOR_GRAY}| Mail: "
status+="${mail_color}${mail_unread}U${COLOR_RESET} "
status+="${COLOR_GRAY}| "
status+="${health_color}${health_icon}"
status+="${COLOR_GRAY}]${COLOR_RESET}"

# Output (echo -e for ANSI, printf for tmux)
if [[ -n "${TMUX:-}" ]]; then
    printf "%s" "$status"
else
    echo -e "$status"
fi
