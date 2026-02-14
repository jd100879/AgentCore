#!/usr/bin/env bash
# agent-control.sh - Interactive fzf-based agent communication interface
#
# Enhanced TUI with:
# - Real-time agent status with previews
# - Multi-select broadcasting
# - Task tracking and mail counts
# - Keyboard shortcuts
# - Editor support for long messages
#
# Dependencies: fzf (0.27+), tmux, jq
# Keyboard shortcuts:
#   Ctrl-A: Select all    Ctrl-T: Toggle selection
#   Ctrl-R: Refresh       Ctrl-H: Help
#   Tab: Multi-select     Enter: Confirm

set -euo pipefail

# Allow glob patterns that don't match to expand to nothing
shopt -s nullglob

# Resolve real path (symlink-aware)
if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 required for path resolution" >&2
  exit 1
fi
SCRIPT_PATH="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source shared project configuration
source "$SCRIPT_DIR/lib/project-config.sh"

# Cache file for performance
CACHE_DIR="$PIDS_DIR/.cache"
AGENTS_CACHE="$CACHE_DIR/agents.cache"
CACHE_TTL=10  # seconds

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
GRAY='\033[0;90m'
NC='\033[0m'

# FZF configuration - use tmux popup mode if inside tmux
if [ -n "${TMUX:-}" ]; then
    FZF_TMUX_OPTS="--tmux center,90%,80%"
else
    FZF_TMUX_OPTS=""
fi

# Create cache dir
mkdir -p "$CACHE_DIR"

# Check dependencies
check_dependencies() {
    local missing=()
    for cmd in fzf tmux jq; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}Error: Missing dependencies: ${missing[*]}${NC}" >&2
        exit 1
    fi
}

# Get unread mail count for agent
get_mail_count() {
    local agent="$1"
    local count=0

    if [ -f "$PROJECT_ROOT/.beads/mail-read.jsonl" ]; then
        # Count messages where agent hasn't read them
        count=$("$SCRIPT_DIR/agent-mail-helper.sh" unread 2>/dev/null | grep -c "$agent" || echo "0")
    fi

    echo "$count"
}

# Get current task for agent from beads
get_current_task() {
    local agent="$1"
    local task=""

    # Check swarm state files
    for state_file in "$PROJECT_ROOT/pids"/swarm-*.state; do
        [ -f "$state_file" ] || continue
        task=$(jq -r --arg name "$agent" '.agents[] | select(.name == $name) | .current_task // empty' "$state_file" 2>/dev/null || echo "")
        [ -n "$task" ] && break
    done

    # Fallback: check beads for in_progress tasks owned by this agent
    if [ -z "$task" ] && [ -f "$PROJECT_ROOT/.beads/issues.jsonl" ]; then
        task=$(jq -r --arg agent "$agent" 'select(.status == "in_progress" and .owner == $agent) | .id + ": " + .title' "$PROJECT_ROOT/.beads/issues.jsonl" 2>/dev/null | head -1 || echo "")
    fi

    echo "${task:-idle}"
}

# Get enhanced agent list with status, task, mail count
get_agents_list() {
    # Check cache freshness
    if [ -f "$AGENTS_CACHE" ]; then
        local cache_age=$(($(date +%s) - $(stat -f %m "$AGENTS_CACHE" 2>/dev/null || stat -c %Y "$AGENTS_CACHE" 2>/dev/null || echo 0)))
        if [ "$cache_age" -lt "$CACHE_TTL" ]; then
            cat "$AGENTS_CACHE"
            return
        fi
    fi

    [ ! -d "$PANES_DIR" ] && return

    local output=""
    while IFS= read -r identity_file; do
        [ -f "$identity_file" ] || continue

        local agent_name=$(jq -r '.agent_mail_name // empty' "$identity_file" 2>/dev/null)
        [ -z "$agent_name" ] && continue

        local pane=$(jq -r '.pane // empty' "$identity_file" 2>/dev/null)
        local status="inactive"
        local last_activity=""

        if [ -n "$pane" ] && tmux list-panes -a -F "#{pane_id}" 2>/dev/null | grep -q "^$pane$"; then
            status="active"
            # Get last activity from tmux
            last_activity=$(tmux display-message -t "$pane" -p "#{pane_activity_string}" 2>/dev/null || echo "unknown")
        fi

        local task=$(get_current_task "$agent_name")
        local mail_count=$(get_mail_count "$agent_name")

        output+="${agent_name}|${status}|${task}|${mail_count}|${pane}|${last_activity}
"
    done < <(find "$PANES_DIR" -name "*.identity" -type f 2>/dev/null)

    # Cache the result
    echo -n "$output" > "$AGENTS_CACHE"
    echo -n "$output"
}

# Force refresh agent cache
refresh_agents_cache() {
    rm -f "$AGENTS_CACHE"
    get_agents_list > /dev/null
}

# Generate preview for agent
preview_agent() {
    local agent_line="$1"
    IFS='|' read -r name status task mail_count pane last_activity <<< "$agent_line"

    echo -e "${BLUE}╔══════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC} Agent: ${CYAN}${name}${NC}"
    echo -e "${BLUE}╠══════════════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC} Status: $([ "$status" = "active" ] && echo -e "${GREEN}● Active${NC}" || echo -e "${GRAY}○ Inactive${NC}")"
    echo -e "${BLUE}║${NC} Task: ${YELLOW}${task}${NC}"
    echo -e "${BLUE}║${NC} Unread mail: ${MAGENTA}${mail_count}${NC}"
    [ -n "$last_activity" ] && echo -e "${BLUE}║${NC} Last activity: ${GRAY}${last_activity}${NC}"
    echo -e "${BLUE}╚══════════════════════════════════╝${NC}"
    echo ""

    # Show recent mail
    if [ "$mail_count" -gt 0 ]; then
        echo -e "${CYAN}Recent mail:${NC}"
        "$SCRIPT_DIR/agent-mail-helper.sh" inbox 2>/dev/null | grep "$name" | head -3 || echo "  (none)"
    fi

    echo ""

    # Show current pane content if active
    if [ "$status" = "active" ] && [ -n "$pane" ]; then
        echo -e "${CYAN}Pane snapshot:${NC}"
        tmux capture-pane -t "$pane" -p 2>/dev/null | tail -10 || echo "  (not available)"
    fi
}

# Show help
show_help() {
    cat <<EOF | less
Agent Control Panel - Help

KEYBOARD SHORTCUTS:
  Tab          Multi-select mode (in agent/broadcast views)
  Ctrl-A       Select all
  Ctrl-R       Refresh agent list
  Ctrl-H       Show this help
  Ctrl-C       Cancel/Back
  Enter        Confirm selection

MAIN MENU:
  📢 Broadcast   Send messages to multiple agents (supports multi-select)
  👥 View        View agent details with live previews
  📧 Mail        Check your mail inbox
  📊 Fleet       Show fleet dashboard with metrics
  🔍 Search      Search agent session history
  🚀 Spawn       Create new agent swarm
  ⚙️  Manage     Manage running swarms

BROADCAST MODES:
  @all           All agents in project
  @active        Only currently active agents
  Multi-select   Choose specific agents (Tab to select, Enter to confirm)

MESSAGE TYPES:
  FYI           Informational (normal priority)
  UPDATE        Progress update
  QUESTION      Requires response
  URGENT        High priority, immediate attention
  BLOCKER       Work is blocked, needs resolution
  HANDOFF       Task transfer
  COMPLETED     Task done notification

TIPS:
  • Use Ctrl-R to refresh agent list when status changes
  • Multi-select allows targeted broadcasts to specific agents
  • Preview pane shows agent status, current task, and recent mail
  • Messages can be edited with \$EDITOR for longer content

Press Q to exit help
EOF
}

# Main menu
show_main_menu() {
    local choice=$(cat <<EOF | fzf $FZF_TMUX_OPTS \
        --height=40% \
        --border \
        --prompt="Agent Control > " \
        --header="Ctrl-H: Help | Ctrl-R: Refresh | Ctrl-C: Exit" \
        --bind='ctrl-h:execute(bash -c "source ${BASH_SOURCE[0]}; show_help")' \
        --bind='ctrl-r:reload(echo -e "📢 Broadcast message to agents\n👥 View agent status\n📧 Check mail inbox\n📊 Fleet dashboard\n🔍 Search history\n🚀 Spawn swarm\n⚙️  Manage swarms\n❌ Exit")' \
        --ansi
📢 Broadcast message to agents
👥 View agent status
📧 Check mail inbox
📊 Fleet dashboard
🔍 Search history
🚀 Spawn swarm
⚙️  Manage swarms
❓ Help
❌ Exit
EOF
)
    case "$choice" in
        "📢 Broadcast"*) broadcast_menu ;;
        "👥 View"*) view_agents_menu ;;
        "📧 Check"*) "$SCRIPT_DIR/agent-mail-helper.sh" inbox | less; read -p "Press Enter..."; show_main_menu ;;
        "📊 Fleet"*) "$SCRIPT_DIR/fleet-status.sh"; read -p "Press Enter..."; show_main_menu ;;
        "🔍 Search"*) search_menu ;;
        "🚀 Spawn"*) spawn_menu ;;
        "⚙️  Manage"*) manage_menu ;;
        "❓ Help"*) show_help; show_main_menu ;;
        "❌ Exit") exit 0 ;;
        *) [ -n "$choice" ] && show_main_menu || exit 0 ;;
    esac
}

# Broadcast menu with multi-select support
broadcast_menu() {
    local broadcast_mode=$(cat <<EOF | fzf $FZF_TMUX_OPTS --height=40% --border --prompt="Broadcast mode > " --header="Select target mode"
@all                     All agents in project
@active                  Active agents only
Multi-select agents      Choose specific agents (recommended)
Back
EOF
)

    [[ "$broadcast_mode" =~ Back ]] && show_main_menu && return

    local targets=()
    local group_name=""

    if [[ "$broadcast_mode" =~ Multi-select ]]; then
        # Multi-select specific agents
        local agents=$(get_agents_list)
        [ -z "$agents" ] && echo -e "${YELLOW}No agents found${NC}" && read -p "Press Enter..." && show_main_menu && return

        local selected=$(echo "$agents" | while IFS='|' read -r name status task mail_count pane activity; do
            local icon=$([ "$status" = "active" ] && echo "●" || echo "○")
            local task_short=$(echo "$task" | cut -c1-40)
            printf "%-2s %-20s %s\n" "$icon" "$name" "$task_short"
        done | fzf $FZF_TMUX_OPTS \
            --multi \
            --height=80% \
            --border \
            --prompt="Select agents (Tab to mark, Enter when done) > " \
            --header="Tab: Select | Ctrl-A: Select all | Enter: Confirm" \
            --bind='ctrl-a:select-all' \
            --preview="echo '{}' | awk '{print \$2}' | xargs -I{} grep '{}' $AGENTS_CACHE | xargs -I{} bash -c 'source ${BASH_SOURCE[0]}; preview_agent \"{}\"'" \
            --preview-window=right:50% \
            --ansi)

        [ -z "$selected" ] && broadcast_menu && return

        # Extract agent names
        while IFS= read -r line; do
            local agent=$(echo "$line" | awk '{print $2}')
            targets+=("$agent")
        done <<< "$selected"

        group_name="custom (${#targets[@]} agents)"
    else
        # Use group broadcast
        group_name=$(echo "$broadcast_mode" | awk '{print $1}')
    fi

    # Select message type
    local msg_type=$(cat <<EOF | fzf $FZF_TMUX_OPTS --height=40% --border --prompt="Message type > " --header="Select priority and type"
FYI               Informational, no action required
UPDATE            Progress update
QUESTION          Requires response from recipients
URGENT            High priority, immediate attention needed
BLOCKER           Work blocked, needs resolution
HANDOFF           Task handoff to other agent(s)
COMPLETED         Task completion notification
EOF
)
    [ -z "$msg_type" ] && broadcast_menu && return
    msg_type=$(echo "$msg_type" | awk '{print $1}')

    # Get subject
    echo -e "\n${CYAN}Enter subject:${NC}"
    read -r subject
    [ -z "$subject" ] && broadcast_menu && return

    # Get message (with editor support for long messages)
    echo -e "${CYAN}Enter message (or press 'e' for editor):${NC}"
    read -r message_input

    if [ "$message_input" = "e" ]; then
        local tmpfile=$(mktemp)
        ${EDITOR:-nano} "$tmpfile"
        message=$(cat "$tmpfile")
        rm -f "$tmpfile"
    else
        message="$message_input"
    fi

    [ -z "$message" ] && broadcast_menu && return

    # Preview
    echo -e "\n${BLUE}━━━ Broadcast Preview ━━━${NC}"
    if [ ${#targets[@]} -gt 0 ]; then
        echo -e "To: ${GREEN}${targets[*]}${NC}"
    else
        echo -e "To: ${GREEN}$group_name${NC}"
    fi
    echo -e "Type: ${YELLOW}$msg_type${NC}"
    echo -e "Subject: ${CYAN}$subject${NC}"
    echo -e "Message:"
    echo -e "${GRAY}${message}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    read -p "Send broadcast? [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        if [ ${#targets[@]} -gt 0 ]; then
            # Send to each selected agent
            for agent in "${targets[@]}"; do
                "$SCRIPT_DIR/agent-mail-helper.sh" send "$agent" "[$msg_type] $subject" "$message" &
            done
            wait
            echo -e "${GREEN}✓ Sent to ${#targets[@]} agent(s)${NC}"
        else
            # Use broadcast script for groups
            "$SCRIPT_DIR/broadcast-to-swarm.sh" "$group_name" "$subject" "$message" --type "$msg_type"
        fi
        read -p "Press Enter..."
    fi
    show_main_menu
}

# View agents menu with enhanced preview
view_agents_menu() {
    refresh_agents_cache  # Refresh before showing
    local agents=$(get_agents_list)

    [ -z "$agents" ] && echo -e "${YELLOW}No agents found${NC}" && read -p "Press Enter..." && show_main_menu && return

    local selected=$(echo "$agents" | while IFS='|' read -r name status task mail_count pane activity; do
        local icon=$([ "$status" = "active" ] && echo -e "${GREEN}●${NC}" || echo -e "${GRAY}○${NC}")
        local mail_badge=""
        [ "$mail_count" -gt 0 ] && mail_badge="📧${mail_count}"
        local task_short=$(echo "$task" | cut -c1-35)
        [ "$task" = "idle" ] && task_short="${GRAY}${task}${NC}"

        printf "%b %-20s %-38s %s\n" "$icon" "$name" "$task_short" "$mail_badge"
    done | fzf $FZF_TMUX_OPTS \
        --height=90% \
        --border \
        --prompt="Agents (Ctrl-R: Refresh) > " \
        --header="● Active  ○ Inactive | Select agent for details" \
        --bind="ctrl-r:reload(bash -c 'source ${BASH_SOURCE[0]}; refresh_agents_cache; get_agents_list' | while IFS='|' read -r name status task mail_count pane activity; do local icon=\$([ \"\$status\" = \"active\" ] && echo -e \"${GREEN}●${NC}\" || echo -e \"${GRAY}○${NC}\"); local mail_badge=\"\"; [ \"\$mail_count\" -gt 0 ] && mail_badge=\"📧\${mail_count}\"; local task_short=\$(echo \"\$task\" | cut -c1-35); printf \"%b %-20s %-38s %s\\n\" \"\$icon\" \"\$name\" \"\$task_short\" \"\$mail_badge\"; done)" \
        --preview="echo '{}' | awk '{print \$2}' | xargs -I{} grep '{}' $AGENTS_CACHE | xargs -I{} bash -c 'source ${BASH_SOURCE[0]}; preview_agent \"{}\"'" \
        --preview-window=right:55% \
        --ansi)

    if [ -n "$selected" ]; then
        local agent_name=$(echo "$selected" | awk '{print $2}')
        agent_menu "$agent_name"
    fi

    show_main_menu
}

# Agent detail menu
agent_menu() {
    local agent="$1"

    # Get agent details
    local agent_data=$(grep "$agent" "$AGENTS_CACHE" 2>/dev/null || echo "$agent|unknown||||")
    IFS='|' read -r name status task mail_count pane activity <<< "$agent_data"

    local choice=$(cat <<EOF | fzf $FZF_TMUX_OPTS \
        --height=50% \
        --border \
        --prompt="$agent > " \
        --header="Status: $status | Task: $task | Mail: $mail_count" \
        --preview="bash -c 'source ${BASH_SOURCE[0]}; preview_agent \"$agent_data\"'" \
        --preview-window=right:60%
📧 View inbox ($mail_count unread)
💬 Send direct message
📋 View current task details
🔍 View agent history
🔄 Assign new task
📊 View metrics
🔙 Back to agent list
EOF
)
    case "$choice" in
        "📧 View inbox"*)
            echo -e "\n${CYAN}Inbox for $agent:${NC}\n"
            "$SCRIPT_DIR/agent-mail-helper.sh" inbox 2>/dev/null | grep -A5 "$agent" | less
            read -p "Press Enter..."
            agent_menu "$agent"
            ;;
        "💬 Send"*)
            echo -e "\n${CYAN}Subject:${NC}"
            read -r subj
            [ -z "$subj" ] && agent_menu "$agent" && return

            echo -e "${CYAN}Message (or 'e' for editor):${NC}"
            read -r msg_input

            if [ "$msg_input" = "e" ]; then
                local tmpfile=$(mktemp)
                ${EDITOR:-nano} "$tmpfile"
                msg=$(cat "$tmpfile")
                rm -f "$tmpfile"
            else
                msg="$msg_input"
            fi

            [ -z "$msg" ] && agent_menu "$agent" && return

            "$SCRIPT_DIR/agent-mail-helper.sh" send "$agent" "$subj" "$msg"
            echo -e "${GREEN}✓ Message sent to $agent${NC}"
            read -p "Press Enter..."
            agent_menu "$agent"
            ;;
        "📋 View current"*)
            if [ "$task" != "idle" ]; then
                echo -e "\n${CYAN}Current task for $agent:${NC}\n"
                # Try to get task details from beads
                local task_id=$(echo "$task" | grep -oE 'bd-[a-z0-9]+' | head -1)
                if [ -n "$task_id" ] && [ -f "$PROJECT_ROOT/.beads/issues.jsonl" ]; then
                    jq -r --arg id "$task_id" 'select(.id == $id)' "$PROJECT_ROOT/.beads/issues.jsonl" | jq '.'
                else
                    echo "$task"
                fi
            else
                echo -e "\n${GRAY}$agent is currently idle${NC}"
            fi
            read -p "Press Enter..."
            agent_menu "$agent"
            ;;
        "🔍 View agent"*)
            echo -e "\n${CYAN}Searching history for $agent:${NC}\n"
            "$SCRIPT_DIR/search-history.sh" "$agent" 2>/dev/null | less
            read -p "Press Enter..."
            agent_menu "$agent"
            ;;
        "🔄 Assign"*)
            echo -e "\n${CYAN}Available tasks:${NC}\n"
            # Show ready beads tasks
            if command -v br &> /dev/null; then
                br ready | head -20
            else
                jq -r 'select(.status == "ready") | "\(.id): \(.title)"' "$PROJECT_ROOT/.beads/issues.jsonl" 2>/dev/null | head -20
            fi
            echo -e "\n${CYAN}Enter task ID to assign (or blank to cancel):${NC}"
            read -r task_id

            if [ -n "$task_id" ]; then
                # Send assignment via mail
                "$SCRIPT_DIR/agent-mail-helper.sh" send "$agent" "[HANDOFF] Task $task_id assigned" "You have been assigned task $task_id. Please review and claim it."
                echo -e "${GREEN}✓ Task assignment sent${NC}"
            fi
            read -p "Press Enter..."
            agent_menu "$agent"
            ;;
        "📊 View metrics"*)
            echo -e "\n${CYAN}Metrics for $agent:${NC}\n"
            # Show agent metrics if available
            if [ -f "$PROJECT_ROOT/docs/metrics/fleet-metrics.jsonl" ]; then
                jq -r --arg agent "$agent" 'select(.agent == $agent)' "$PROJECT_ROOT/docs/metrics/fleet-metrics.jsonl" 2>/dev/null | tail -10 | jq '.'
            else
                echo -e "${GRAY}No metrics available${NC}"
            fi
            read -p "Press Enter..."
            agent_menu "$agent"
            ;;
        "🔙 Back"*|"")
            return
            ;;
        *)
            agent_menu "$agent"
            ;;
    esac
}

# Search menu
search_menu() {
    echo -e "\n${CYAN}Search query:${NC}"; read -r query
    [ -n "$query" ] && "$SCRIPT_DIR/search-history.sh" "$query" | less
    read -p "Press Enter..."; show_main_menu
}

# Spawn menu with presets
spawn_menu() {
    local preset=$(cat <<EOF | fzf $FZF_TMUX_OPTS --height=40% --border --prompt="Spawn swarm > " --header="Select swarm size"
Small (2 agents)       Quick pair programming
Medium (4 agents)      Balanced team
Large (6 agents)       Full feature team
XLarge (8 agents)      Complex project
Custom                 Choose specific number
Back
EOF
)

    [[ "$preset" =~ Back ]] && show_main_menu && return

    local num=0
    case "$preset" in
        "Small"*) num=2 ;;
        "Medium"*) num=4 ;;
        "Large"*) num=6 ;;
        "XLarge"*) num=8 ;;
        "Custom"*)
            echo -e "\n${CYAN}Enter number of agents (1-16):${NC}"
            read -r num
            [[ ! "$num" =~ ^[0-9]+$ ]] && echo -e "${RED}Invalid number${NC}" && read -p "Press Enter..." && spawn_menu && return
            ;;
        *) show_main_menu; return ;;
    esac

    echo -e "\n${CYAN}Enter swarm session name (optional, press Enter for auto-name):${NC}"
    read -r session_name

    echo -e "\n${BLUE}Spawning $num agents...${NC}\n"

    if [ -n "$session_name" ]; then
        "$SCRIPT_DIR/spawn-swarm.sh" "$num" "$session_name"
    else
        "$SCRIPT_DIR/spawn-swarm.sh" "$num"
    fi

    echo -e "\n${GREEN}✓ Swarm spawned successfully${NC}"
    read -p "Press Enter..."
    show_main_menu
}

# Manage menu with swarm details
manage_menu() {
    local swarms_data=""

    for state_file in "$PROJECT_ROOT/pids"/swarm-*.state; do
        [ -f "$state_file" ] || continue
        local name=$(basename "$state_file" .state | sed 's/swarm-//')
        local agent_count=$(jq -r '.agents | length' "$state_file" 2>/dev/null || echo "0")
        local active_count=$(jq -r '[.agents[] | select(.status == "active")] | length' "$state_file" 2>/dev/null || echo "0")
        swarms_data+="$name (${active_count}/${agent_count} active)
"
    done

    [ -z "$swarms_data" ] && echo -e "${YELLOW}No active swarms found${NC}" && read -p "Press Enter..." && show_main_menu && return

    local selected=$(echo "$swarms_data" | fzf $FZF_TMUX_OPTS \
        --height=60% \
        --border \
        --prompt="Manage swarms > " \
        --header="Select swarm to manage" \
        --preview="echo '{}' | awk '{print \$1}' | xargs -I{} bash -c 'if [ -f \"$PROJECT_ROOT/pids/swarm-{}.state\" ]; then jq \".\" \"$PROJECT_ROOT/pids/swarm-{}.state\"; fi'" \
        --preview-window=right:50%)

    [ -z "$selected" ] && show_main_menu && return

    local swarm_name=$(echo "$selected" | awk '{print $1}')
    swarm_detail_menu "$swarm_name"
}

# Swarm detail menu
swarm_detail_menu() {
    local swarm="$1"

    local choice=$(cat <<EOF | fzf $FZF_TMUX_OPTS --height=50% --border --prompt="Swarm: $swarm > "
📊 View status
📢 Broadcast to this swarm
🔄 Assign tasks to swarm
🛑 Teardown swarm
🔙 Back
EOF
)

    case "$choice" in
        "📊 View"*)
            echo -e "\n${CYAN}Status for swarm: $swarm${NC}\n"
            "$SCRIPT_DIR/swarm-status.sh" "$swarm" 2>/dev/null | less
            read -p "Press Enter..."
            swarm_detail_menu "$swarm"
            ;;
        "📢 Broadcast"*)
            echo -e "\n${CYAN}Subject:${NC}"
            read -r subject
            [ -z "$subject" ] && swarm_detail_menu "$swarm" && return

            echo -e "${CYAN}Message:${NC}"
            read -r message
            [ -z "$message" ] && swarm_detail_menu "$swarm" && return

            "$SCRIPT_DIR/broadcast-to-swarm.sh" "@swarm:$swarm" "$subject" "$message"
            echo -e "\n${GREEN}✓ Broadcast sent${NC}"
            read -p "Press Enter..."
            swarm_detail_menu "$swarm"
            ;;
        "🔄 Assign"*)
            echo -e "\n${CYAN}Assigning tasks to swarm: $swarm${NC}\n"
            "$SCRIPT_DIR/assign-tasks.sh" "$swarm" 2>/dev/null
            echo -e "\n${GREEN}✓ Tasks assigned${NC}"
            read -p "Press Enter..."
            swarm_detail_menu "$swarm"
            ;;
        "🛑 Teardown"*)
            echo -e "\n${RED}This will terminate all agents in swarm: $swarm${NC}"
            read -p "Are you sure? [y/N] " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                "$SCRIPT_DIR/teardown-swarm.sh" "$swarm" 2>/dev/null
                echo -e "\n${GREEN}✓ Swarm torn down${NC}"
                read -p "Press Enter..."
                manage_menu
            else
                swarm_detail_menu "$swarm"
            fi
            ;;
        "🔙 Back"*|"")
            manage_menu
            ;;
        *)
            swarm_detail_menu "$swarm"
            ;;
    esac
}

# Main
main() {
    check_dependencies
    clear
    echo -e "${BLUE}╔════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}   ${CYAN}Agent Control Panel${NC}           ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════╝${NC}\n"
    show_main_menu
}

main "$@"
