#!/usr/bin/env bash
#
# fleet-status.sh - CLI dashboard for Agent Flywheel fleet management
#
# Usage:
#   ./scripts/fleet-status.sh                              # Full dashboard
#   ./scripts/fleet-status.sh agents tasks                 # Specific sections
#   ./scripts/fleet-status.sh --compact                    # One-line summary
#   ./scripts/fleet-status.sh --watch                      # Auto-refresh every 5s
#   ./scripts/fleet-status.sh --json                       # JSON output
#
# Sections: agents, tasks, reservations, mail, health
#
# Dependencies: fleet-core.sh (Phase 3A)
# Performance: <1s render time

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/project-config.sh"

# Configuration
REFRESH_INTERVAL=5
DEFAULT_SECTIONS="agents tasks reservations mail health"
COMPACT_MODE=false
WATCH_MODE=false
JSON_MODE=false
RECOMMENDATIONS_MODE=false

# Color codes (ANSI)
if [ -t 1 ]; then
    COLOR_RESET='\033[0m'
    COLOR_BOLD='\033[1m'
    COLOR_GREEN='\033[0;32m'
    COLOR_YELLOW='\033[0;33m'
    COLOR_RED='\033[0;31m'
    COLOR_BLUE='\033[0;34m'
    COLOR_GRAY='\033[0;90m'
else
    COLOR_RESET=''
    COLOR_BOLD=''
    COLOR_GREEN=''
    COLOR_YELLOW=''
    COLOR_RED=''
    COLOR_BLUE=''
    COLOR_GRAY=''
fi

# Parse command-line arguments
SECTIONS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --compact)
            COMPACT_MODE=true
            shift
            ;;
        --watch)
            WATCH_MODE=true
            shift
            ;;
        --json)
            JSON_MODE=true
            shift
            ;;
        --recommendations)
            RECOMMENDATIONS_MODE=true
            shift
            ;;
        -h|--help)
            cat <<EOF
Fleet Status Dashboard - CLI Tool

Usage:
  $0 [OPTIONS] [SECTIONS...]

Options:
  --compact         Single-line summary mode
  --watch           Auto-refresh every ${REFRESH_INTERVAL}s (Ctrl+C to exit)
  --json            JSON output for scripting
  --recommendations Show task assignment recommendations
  -h, --help        Show this help

Sections (default: all):
  agents        Active agents and their status
  tasks         Task assignments and progress
  reservations  File locks and expirations
  mail          Agent mail activity
  health        System health monitoring

Examples:
  $0                       # Full dashboard
  $0 agents tasks          # Only agents and tasks sections
  $0 --compact             # One-line summary
  $0 --watch               # Auto-refresh mode
  $0 --json | jq .         # JSON output
  $0 --recommendations     # Show task assignment suggestions

EOF
            exit 0
            ;;
        agents|tasks|reservations|mail|health)
            SECTIONS+=("$1")
            shift
            ;;
        *)
            echo "Error: Unknown option or section: $1" >&2
            echo "Run '$0 --help' for usage" >&2
            exit 1
            ;;
    esac
done

# Default to all sections if none specified
if [ ${#SECTIONS[@]} -eq 0 ]; then
    IFS=' ' read -ra SECTIONS <<< "$DEFAULT_SECTIONS"
fi

# Helper: Check if section is enabled
is_section_enabled() {
    local section="$1"
    for s in "${SECTIONS[@]}"; do
        if [ "$s" = "$section" ]; then
            return 0
        fi
    done
    return 1
}

# Helper: Format time ago from timestamp
time_ago() {
    local timestamp="$1"
    local now=$(date +%s)
    local then=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" "+%s" 2>/dev/null || echo "$now")
    local diff=$((now - then))

    if [ $diff -lt 60 ]; then
        echo "${diff}s ago"
    elif [ $diff -lt 3600 ]; then
        echo "$((diff / 60))m ago"
    elif [ $diff -lt 86400 ]; then
        echo "$((diff / 3600))h ago"
    else
        echo "$((diff / 86400))d ago"
    fi
}

# Display: Full dashboard mode
display_full() {
    local data="$1"

    # Header
    echo -e "${COLOR_BOLD}╔═══════════════════════════════════════════════════════════════╗${COLOR_RESET}"
    echo -e "${COLOR_BOLD}║          AGENT FLYWHEEL - FLEET STATUS                        ║${COLOR_RESET}"

    local updated=$(echo "$data" | jq -r '.timestamp // "unknown"')
    local updated_ago=$(time_ago "$updated")
    printf "${COLOR_BOLD}║          Updated: %s (%s)%-*s║${COLOR_RESET}\n" \
        "$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$updated" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")" \
        "$updated_ago" \
        $((36 - ${#updated_ago})) ""

    echo -e "${COLOR_BOLD}╚═══════════════════════════════════════════════════════════════╝${COLOR_RESET}"
    echo ""

    # Agents section
    if is_section_enabled "agents"; then
        display_agents "$data"
        echo ""
    fi

    # Tasks section
    if is_section_enabled "tasks"; then
        display_tasks "$data"
        echo ""
    fi

    # Recommendations section (if enabled)
    if [ "$RECOMMENDATIONS_MODE" = true ]; then
        display_recommendations
        echo ""
    fi

    # Reservations section
    if is_section_enabled "reservations"; then
        display_reservations "$data"
        echo ""
    fi

    # Mail section
    if is_section_enabled "mail"; then
        display_mail "$data"
        echo ""
    fi

    # Health section
    if is_section_enabled "health"; then
        display_health "$data"
    fi
}

# Display: Agents section
display_agents() {
    local data="$1"

    echo -e "${COLOR_BOLD}┌─ ACTIVE AGENTS ────────────────────────────────────────────────┐${COLOR_RESET}"

    local agents=$(echo "$data" | jq -c '.agents.list[]? // empty' 2>/dev/null)
    if [ -z "$agents" ]; then
        echo -e "${COLOR_GRAY}│ No agents detected                                             │${COLOR_RESET}"
    else
        while IFS= read -r agent; do
            local name=$(echo "$agent" | jq -r '.name // "unknown"')
            local location=$(echo "$agent" | jq -r '.location // "unknown"')
            local command=$(echo "$agent" | jq -r '.command // "unknown"')
            local status=$(echo "$agent" | jq -r '.status // "unknown"')
            local task=$(echo "$agent" | jq -r '.current_task // "idle"')

            # Color code by status
            local status_color="$COLOR_RESET"
            if [ "$status" = "active" ]; then
                status_color="$COLOR_GREEN"
            elif [ "$status" = "idle" ]; then
                status_color="$COLOR_YELLOW"
            fi

            printf "│ ${status_color}%-12s${COLOR_RESET} %-20s [%-8s] %-16s │\n" \
                "$name" "$location" "$command" "$task"
        done <<< "$agents"
    fi

    local total=$(echo "$data" | jq -r '.agents.total // 0')
    local active=$(echo "$data" | jq -r '.agents.active // 0')
    local idle=$(echo "$data" | jq -r '.agents.idle // 0')

    echo "│                                                                 │"
    printf "│ Active: %d/%d agents | Idle: %d%-*s│\n" \
        "$active" "$total" "$idle" \
        $((37 - ${#idle})) ""

    echo -e "${COLOR_BOLD}└─────────────────────────────────────────────────────────────────┘${COLOR_RESET}"
}

# Display: Recommendations section
display_recommendations() {
    echo -e "${COLOR_BOLD}┌─ TASK RECOMMENDATIONS ─────────────────────────────────────────┐${COLOR_RESET}"

    # Get recommendations from fleet-core.sh
    local recommendations
    if ! recommendations=$("$SCRIPT_DIR/fleet-core.sh" get_task_recommendations 2>/dev/null); then
        echo -e "${COLOR_RED}│ Error: Failed to fetch recommendations                         │${COLOR_RESET}"
        echo -e "${COLOR_BOLD}└─────────────────────────────────────────────────────────────────┘${COLOR_RESET}"
        return 1
    fi

    local rec_count=$(echo "$recommendations" | jq 'length')

    if [ "$rec_count" -eq 0 ]; then
        echo -e "${COLOR_GRAY}│ No recommendations available yet                                │${COLOR_RESET}"
        echo -e "${COLOR_GRAY}│                                                                 │${COLOR_RESET}"
        echo -e "${COLOR_GRAY}│ Recommendations are based on historical task completion data.  │${COLOR_RESET}"
        echo -e "${COLOR_GRAY}│ As agents complete tasks with labels, the system will suggest  │${COLOR_RESET}"
        echo -e "${COLOR_GRAY}│ assignments based on past experience.                           │${COLOR_RESET}"
    else
        echo -e "│ Based on agent history, we recommend:                           │"
        echo "│                                                                 │"

        # Display each recommendation
        echo "$recommendations" | jq -c '.[]' | while IFS= read -r rec; do
            local task_id=$(echo "$rec" | jq -r '.task_id // "unknown"')
            local agent=$(echo "$rec" | jq -r '.recommended_agent // "unknown"')
            local confidence=$(echo "$rec" | jq -r '.confidence // 0')

            # Get task title from br
            local task_title=$(br show "$task_id" 2>/dev/null | head -1 | sed 's/^[^·]*· //' | sed 's/ \[.*$//' || echo "")

            # Truncate title if too long
            if [ ${#task_title} -gt 30 ]; then
                task_title="${task_title:0:27}..."
            fi

            # Confidence level
            local confidence_text="★"
            if [ "$confidence" -ge 3 ]; then
                confidence_text="★★★"
            elif [ "$confidence" -ge 2 ]; then
                confidence_text="★★"
            fi

            printf "│   ${COLOR_GREEN}%-10s${COLOR_RESET} → %-12s %-30s %s%-*s│\n" \
                "$task_id" "$agent" "$task_title" "$confidence_text" \
                $((7 - ${#confidence_text})) ""
        done
    fi

    echo "│                                                                 │"
    printf "│ Total recommendations: %-41s│\n" "$rec_count"
    echo -e "${COLOR_BOLD}└─────────────────────────────────────────────────────────────────┘${COLOR_RESET}"
}

# Display: Tasks section
display_tasks() {
    local data="$1"

    echo -e "${COLOR_BOLD}┌─ TASK STATUS ──────────────────────────────────────────────────┐${COLOR_RESET}"

    local ready=$(echo "$data" | jq -r '.tasks.ready // 0')
    local in_progress=$(echo "$data" | jq -r '.tasks.in_progress // 0')
    local blocked=$(echo "$data" | jq -r '.tasks.blocked // 0')
    local completed=$(echo "$data" | jq -r '.tasks.completed_today // 0')

    printf "│ Ready:        %-50s│\n" "$ready tasks"
    printf "│ In Progress:  %-50s│\n" "$in_progress tasks"

    # Show in-progress tasks
    local ip_tasks=$(echo "$data" | jq -c '.tasks.in_progress_list[]? // empty' 2>/dev/null)
    if [ -n "$ip_tasks" ]; then
        while IFS= read -r task; do
            local id=$(echo "$task" | jq -r '.id // "unknown"')
            local agent=$(echo "$task" | jq -r '.agent // "unknown"')
            local title=$(echo "$task" | jq -r '.title // ""')

            # Truncate title if too long
            if [ ${#title} -gt 35 ]; then
                title="${title:0:32}..."
            fi

            printf "│   ${COLOR_GREEN}•${COLOR_RESET} %-10s [%-12s] %-33s│\n" \
                "$id" "$agent" "$title"
        done <<< "$ip_tasks"
    fi

    printf "│ Blocked:      %-50s│\n" "$blocked tasks"
    printf "│ Completed:    %-50s│\n" "$completed tasks today"

    echo -e "${COLOR_BOLD}└─────────────────────────────────────────────────────────────────┘${COLOR_RESET}"
}

# Display: Reservations section
display_reservations() {
    local data="$1"

    echo -e "${COLOR_BOLD}┌─ FILE RESERVATIONS ────────────────────────────────────────────┐${COLOR_RESET}"

    local reservations=$(echo "$data" | jq -c '.reservations.list[]? // empty' 2>/dev/null)
    if [ -z "$reservations" ]; then
        echo -e "${COLOR_GRAY}│ No active reservations                                          │${COLOR_RESET}"
    else
        while IFS= read -r res; do
            local agent=$(echo "$res" | jq -r '.agent // "unknown"')
            local file=$(echo "$res" | jq -r '.file // "unknown"')
            local expires=$(echo "$res" | jq -r '.expires_in // "unknown"')
            local warning=$(echo "$res" | jq -r '.warning // false')

            # Truncate file path if too long
            if [ ${#file} -gt 35 ]; then
                file="...${file: -32}"
            fi

            # Warning indicator
            local warn_indicator=""
            if [ "$warning" = "true" ]; then
                warn_indicator="${COLOR_YELLOW}⚠${COLOR_RESET}"
            fi

            printf "│ %-12s %-35s Expires: %-7s%s│\n" \
                "$agent" "$file" "$expires" "$warn_indicator"
        done <<< "$reservations"
    fi

    local total=$(echo "$data" | jq -r '.reservations.total // 0')
    local expiring=$(echo "$data" | jq -r '.reservations.expiring_soon // 0')

    echo "│                                                                 │"
    if [ "$expiring" -gt 0 ]; then
        printf "│ Total: %d reservations | ${COLOR_YELLOW}⚠️  %d expiring in <1 hour${COLOR_RESET}%-*s│\n" \
            "$total" "$expiring" \
            $((20 - ${#expiring})) ""
    else
        printf "│ Total: %d reservations%-*s│\n" \
            "$total" $((47 - ${#total})) ""
    fi

    echo -e "${COLOR_BOLD}└─────────────────────────────────────────────────────────────────┘${COLOR_RESET}"
}

# Display: Mail section
display_mail() {
    local data="$1"

    echo -e "${COLOR_BOLD}┌─ AGENT MAIL ───────────────────────────────────────────────────┐${COLOR_RESET}"

    local unread_total=$(echo "$data" | jq -r '.mail.unread_total // 0')

    # Unread counts by agent
    local unread_list=""
    local agents=$(echo "$data" | jq -r '.mail.unread_by_agent | keys[]?' 2>/dev/null)
    if [ -n "$agents" ]; then
        while IFS= read -r agent; do
            local count=$(echo "$data" | jq -r ".mail.unread_by_agent.\"$agent\" // 0")
            if [ "$count" -gt 0 ]; then
                if [ -n "$unread_list" ]; then
                    unread_list+=", "
                fi
                unread_list+="$agent ($count)"
            fi
        done <<< "$agents"
    fi

    if [ -z "$unread_list" ]; then
        unread_list="None"
    fi

    printf "│ Unread: %-56s│\n" "$unread_list"
    echo "│                                                                 │"
    echo "│ Recent:                                                         │"

    # Recent messages
    local recent=$(echo "$data" | jq -c '.mail.recent[]? // empty' 2>/dev/null | head -3)
    if [ -z "$recent" ]; then
        echo -e "${COLOR_GRAY}│   No recent messages                                            │${COLOR_RESET}"
    else
        while IFS= read -r msg; do
            local thread=$(echo "$msg" | jq -r '.thread // "unknown"')
            local from=$(echo "$msg" | jq -r '.from // "unknown"')
            local to=$(echo "$msg" | jq -r '.to // "unknown"')
            local subject=$(echo "$msg" | jq -r '.subject // ""')
            local time_ago=$(echo "$msg" | jq -r '.time_ago // "unknown"')

            # Truncate subject if too long
            if [ ${#subject} -gt 25 ]; then
                subject="${subject:0:22}..."
            fi

            printf "│   [%-10s] %-10s → %-10s %-22s %s│\n" \
                "$thread" "$from" "$to" "$subject" "$time_ago"
        done <<< "$recent"
    fi

    echo -e "${COLOR_BOLD}└─────────────────────────────────────────────────────────────────┘${COLOR_RESET}"
}

# Display: Health section
display_health() {
    local data="$1"

    echo -e "${COLOR_BOLD}┌─ SYSTEM HEALTH ────────────────────────────────────────────────┐${COLOR_RESET}"

    local mail_monitor=$(echo "$data" | jq -r '.health.mail_monitor.status // "unknown"')
    local mail_monitor_panes=$(echo "$data" | jq -r '.health.mail_monitor.panes // 0')
    local hook_bypass=$(echo "$data" | jq -r '.health.hook_bypass.status // "unknown"')
    local hook_warning=$(echo "$data" | jq -r '.health.hook_bypass.warning // false')
    local mcp_mail=$(echo "$data" | jq -r '.health.mcp_agent_mail.status // "unknown"')
    local beads=$(echo "$data" | jq -r '.health.beads_server.status // "unknown"')

    # Mail monitor
    local mm_indicator="${COLOR_RED}✗${COLOR_RESET}"
    if [ "$mail_monitor" = "running" ]; then
        mm_indicator="${COLOR_GREEN}✓${COLOR_RESET}"
    fi
    printf "│ Mail Monitor:     %b %-45s│\n" "$mm_indicator" "$mail_monitor ($mail_monitor_panes panes)"

    # Hook bypass
    local hb_indicator="${COLOR_GREEN}✓${COLOR_RESET}"
    local hb_text="$hook_bypass"
    if [ "$hook_warning" = "true" ]; then
        hb_indicator="${COLOR_YELLOW}⚠${COLOR_RESET}"
        hb_text="$hook_bypass (testing mode)"
    fi
    printf "│ Hook Bypass:      %b %-45s│\n" "$hb_indicator" "$hb_text"

    # MCP Agent Mail
    local mcp_indicator="${COLOR_RED}✗${COLOR_RESET}"
    if [ "$mcp_mail" = "connected" ]; then
        mcp_indicator="${COLOR_GREEN}✓${COLOR_RESET}"
    fi
    printf "│ MCP Agent Mail:   %b %-45s│\n" "$mcp_indicator" "$mcp_mail"

    # Beads
    local beads_indicator="${COLOR_RED}✗${COLOR_RESET}"
    if [ "$beads" = "operational" ]; then
        beads_indicator="${COLOR_GREEN}✓${COLOR_RESET}"
    fi
    printf "│ Beads Server:     %b %-45s│\n" "$beads_indicator" "$beads"

    echo -e "${COLOR_BOLD}└─────────────────────────────────────────────────────────────────┘${COLOR_RESET}"
}

# Display: Compact mode
display_compact() {
    local data="$1"

    local agents_active=$(echo "$data" | jq -r '.agents.active // 0')
    local agents_total=$(echo "$data" | jq -r '.agents.total // 0')
    local tasks_ready=$(echo "$data" | jq -r '.tasks.ready // 0')
    local tasks_ip=$(echo "$data" | jq -r '.tasks.in_progress // 0')
    local files_total=$(echo "$data" | jq -r '.reservations.total // 0')
    local files_expiring=$(echo "$data" | jq -r '.reservations.expiring_soon // 0')
    local mail_unread=$(echo "$data" | jq -r '.mail.unread_total // 0')
    local health=$(echo "$data" | jq -r '.health.overall // "unknown"')

    local health_indicator="✓"
    if [ "$health" != "healthy" ]; then
        health_indicator="⚠"
    fi

    local expiring_note=""
    if [ "$files_expiring" -gt 0 ]; then
        expiring_note=" ($files_expiring expiring)"
    fi

    echo "FLEET: $agents_active/$agents_total active | Tasks: $tasks_ready ready, $tasks_ip in-progress | Files: $files_total locked$expiring_note | Mail: $mail_unread unread | Health: $health_indicator"
}

# Display: JSON mode
display_json() {
    local data="$1"
    echo "$data" | jq .
}

# Main render function
render_dashboard() {
    # Get aggregated data from fleet-core.sh
    local data
    if ! data=$("$SCRIPT_DIR/fleet-core.sh" aggregate 2>/dev/null); then
        echo "Error: Failed to aggregate fleet data. Is fleet-core.sh available?" >&2
        return 1
    fi

    if [ "$JSON_MODE" = true ]; then
        display_json "$data"
    elif [ "$COMPACT_MODE" = true ]; then
        display_compact "$data"
    else
        display_full "$data"
    fi
}

# Watch mode loop
watch_loop() {
    while true; do
        if [ "$COMPACT_MODE" = false ] && [ "$JSON_MODE" = false ]; then
            clear
        fi

        render_dashboard

        if [ "$COMPACT_MODE" = false ] && [ "$JSON_MODE" = false ]; then
            echo ""
            echo -e "${COLOR_GRAY}Next refresh in: ${REFRESH_INTERVAL}s | Press Ctrl+C to exit${COLOR_RESET}"
        fi

        sleep "$REFRESH_INTERVAL"
    done
}

# Main execution
main() {
    if [ "$WATCH_MODE" = true ]; then
        watch_loop
    else
        render_dashboard
    fi
}

main "$@"
