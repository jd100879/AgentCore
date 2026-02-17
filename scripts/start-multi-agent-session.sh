#!/bin/bash
# Interactive Multi-Agent Tmux Session Creator V2
# Creates a tmux session with Claude and Codex agents with bypass permissions
# NEW: Adds support for shared task lists via CLAUDE_CODE_TASK_LIST_ID

set -e

# Resolve real path (symlink-aware)
if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 required for path resolution" >&2
  exit 1
fi
SCRIPT_PATH="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
readonly AGENTCORE_ROOT="$(dirname "$SCRIPT_DIR")"

# Help message
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  echo "Usage: $0"
  echo "Interactive Multi-Agent Tmux Session Creator"
  echo ""
  echo "Creates a tmux session with Claude and Codex agents with bypass permissions"
  echo "Supports shared task lists via CLAUDE_CODE_TASK_LIST_ID"
  exit 0
fi

# Configuration Constants
readonly MAX_AGENTS_WARNING=10
readonly HISTORY_LIMIT=50000
readonly AGENT_INIT_WAIT=5
readonly REGISTRATION_SETTLE_WAIT=2
readonly LOG_DIR="$HOME/.agent-flywheel"
readonly LOG_FILE="$LOG_DIR/session-creation.log"
readonly FLYWHEEL_DIR="$AGENTCORE_ROOT"  # For backward compatibility, use dynamic root
readonly REQUIRED_MAIL_SCRIPTS=()  # Sync handled by sync-beads-to-project.sh
readonly REQUIRED_MAIL_DIRS=()

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Logging function
log() {
    mkdir -p "$LOG_DIR"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Dependency check function
check_dependencies() {
    local missing=()
    command -v tmux >/dev/null || missing+=("tmux")
    command -v jq >/dev/null || missing+=("jq")
    command -v docker >/dev/null || missing+=("docker")

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}Error: Missing required dependencies: ${missing[*]}${NC}"
        log "ERROR: Missing dependencies: ${missing[*]}"
        exit 1
    fi
    log "Dependency check passed"
}

# Sync scripts for an existing session before attaching
sync_scripts_for_session() {
    local session_name="$1"
    # Get project path from the first pane's working directory
    local session_project_path
    session_project_path=$(tmux display-message -t "$session_name:1.1" -p "#{pane_current_path}" 2>/dev/null || \
                          tmux display-message -t "$session_name" -p "#{pane_current_path}" 2>/dev/null || echo "")

    if [ -n "$session_project_path" ] && [ -d "$session_project_path" ]; then
        PROJECT_PATH="$session_project_path"
        echo -e "${DIM}Syncing scripts to ${PROJECT_PATH/#$HOME/\~}...${NC}"
        ensure_mail_scripts_available
    fi
}

ensure_mail_scripts_available() {
    # Delegate to the canonical sync script (single source of truth)
    if [ -f "$FLYWHEEL_DIR/scripts/sync-beads-to-project.sh" ]; then
        bash "$FLYWHEEL_DIR/scripts/sync-beads-to-project.sh" "$PROJECT_PATH" 2>/dev/null || true
    fi
}

# Create AGENT_MAIL.md documentation
create_agent_mail_docs() {
    local agent_mail_md="$PROJECT_PATH/AGENT_MAIL.md"

    cat > "$agent_mail_md" << 'EOF'
# Agent Mail System

This project has multi-agent communication enabled via MCP Agent Mail.

## Commands

All commands use the agent-mail-helper.sh script in ./scripts/

### Check your agent identity
```bash
./scripts/agent-mail-helper.sh whoami
```

### List all agents
```bash
./scripts/agent-mail-helper.sh list
```

### Send a message
```bash
./scripts/agent-mail-helper.sh send 'RecipientName' 'Subject' 'Message body'
```

### Check inbox
```bash
./scripts/agent-mail-helper.sh inbox
```

### Notifications monitor (tmux banner)
```bash
./scripts/mail-monitor-ctl.sh start
```

## Server check

Agent mail requires the MCP Agent Mail server to be running (port 8765).

Quick check:
```bash
docker ps | grep 8765
```

If it's not running:
```bash
cd "$MCP_AGENT_MAIL_DIR" && docker-compose up -d
```

## Troubleshooting

### Not receiving notifications (but inbox has messages)
1) Check monitor status:
```bash
./scripts/mail-monitor-ctl.sh status
```
2) Restart monitor (binds to current pane):
```bash
./scripts/mail-monitor-ctl.sh restart
```
3) Verify this pane has an agent name:
```bash
cat ./pids/$(tmux display-message -p "#{session_name}:#{window_index}.#{pane_index}" | tr ':.' '-').agent-name
```

### Not receiving messages at all
```bash
./scripts/agent-mail-helper.sh inbox
```

## Hook Bypass Utility

For testing purposes, you can temporarily bypass Claude Code hooks.

### Enable bypass
```bash
./scripts/hook-bypass.sh on
```

### Disable bypass
```bash
./scripts/hook-bypass.sh off
```

### Check status
```bash
./scripts/hook-bypass.sh status
```

When bypass is enabled, a warning indicator will appear in the tmux pane borders and status bar.

## Examples

```bash
# See who you are
./scripts/agent-mail-helper.sh whoami

# See all agents in this project
./scripts/agent-mail-helper.sh list

# Send a message
./scripts/agent-mail-helper.sh send 'CloudyBadger' 'Status' 'Feature X complete'

# Check recent messages
./scripts/agent-mail-helper.sh inbox 5
```
EOF

    echo -e "${GREEN}✓ Created AGENT_MAIL.md${NC}"
    log "Created AGENT_MAIL.md"
}

# Add reference to AGENT_MAIL.md in CLAUDE.md
sync_agents_md() {
    local source_agents_md="$FLYWHEEL_DIR/AGENTS.md"
    local dest_agents_md="$PROJECT_PATH/AGENTS.md"

    if [ "$source_agents_md" = "$dest_agents_md" ]; then
        log "Skipping AGENTS.md sync (source == destination)"
        return
    fi

    if [ ! -f "$source_agents_md" ]; then
        echo -e "${YELLOW}Warning: AGENTS.md not found at $source_agents_md${NC}"
        return
    fi

    if [ -f "$dest_agents_md" ]; then
        if cmp -s "$source_agents_md" "$dest_agents_md"; then
            log "AGENTS.md already up to date"
            return
        fi
    fi

    cp "$source_agents_md" "$dest_agents_md"
    echo -e "${GREEN}✓ Synced AGENTS.md to project${NC}"
    log "Synced AGENTS.md to $dest_agents_md"
}

update_claude_md_reference() {
    local claude_md="$PROJECT_PATH/CLAUDE.md"
    local ref_text='

---

📧 **Multi-Agent Communication**: See [AGENT_MAIL.md](./AGENT_MAIL.md) for commands.

🎯 **Beads Workflow**: See [AGENTS.md](./AGENTS.md) for task tracking with BV.
'

    if [ -f "$claude_md" ]; then
        local needs_update=false

        if ! grep -qF '[AGENT_MAIL.md]' "$claude_md" 2>/dev/null; then
            needs_update=true
        fi

        if ! grep -qF '[AGENTS.md]' "$claude_md" 2>/dev/null; then
            needs_update=true
        fi

        if [ "$needs_update" = true ]; then
            # Only add lines that don't exist
            [ -s "$claude_md" ] && [ "$(tail -c1 "$claude_md" 2>/dev/null | wc -l)" -eq 0 ] && echo "" >> "$claude_md"

            if ! grep -qF '[AGENT_MAIL.md]' "$claude_md" 2>/dev/null; then
                echo -e "\n📧 **Multi-Agent Communication**: See [AGENT_MAIL.md](./AGENT_MAIL.md) for commands." >> "$claude_md"
                echo -e "${GREEN}✓ Added AGENT_MAIL.md reference to CLAUDE.md${NC}"
            fi

            if ! grep -qF '[AGENTS.md]' "$claude_md" 2>/dev/null; then
                echo -e "\n🎯 **Beads Workflow**: See [AGENTS.md](./AGENTS.md) for task tracking with BV." >> "$claude_md"
                echo -e "${GREEN}✓ Added AGENTS.md reference to CLAUDE.md${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️  CLAUDE.md already has all references${NC}"
        fi
    else
        cat > "$claude_md" << 'EOF'
# Project Instructions

📧 **Multi-Agent Communication**: See [AGENT_MAIL.md](./AGENT_MAIL.md) for commands.

🎯 **Beads Workflow**: See [AGENTS.md](./AGENTS.md) for task tracking with BV.
EOF
        echo -e "${GREEN}✓ Created CLAUDE.md${NC}"
    fi
}

log "=== Session creation started ==="
check_dependencies

# Manage existing sessions (attach, kill, or create new)
manage_existing_sessions() {
    local sessions=()
    local session_info=()

    # Get all tmux sessions
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            local session_name=$(echo "$line" | cut -d: -f1)
            local attached=$(echo "$line" | cut -d: -f2)
            local pane_count=$(tmux list-panes -t "$session_name" 2>/dev/null | wc -l | tr -d ' ')
            local status="detached"
            [ "$attached" != "0" ] && status="attached"

            sessions+=("$session_name")
            session_info+=("$session_name|$pane_count|$status")
        fi
    done < <(tmux list-sessions -F "#{session_name}:#{session_attached}" 2>/dev/null || true)

    # If no sessions exist, skip this
    if [ ${#sessions[@]} -eq 0 ]; then
        return 0
    fi

    # Display existing sessions
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Existing Tmux Sessions (Multi-Agent Coding Environments)      ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}💡 You have existing coding sessions. You can:${NC}"
    echo -e "${YELLOW}   • Attach = Resume working in that session${NC}"
    echo -e "${YELLOW}   • Kill = Permanently delete that session${NC}"
    echo ""

    for i in "${!sessions[@]}"; do
        local info="${session_info[$i]}"
        local name=$(echo "$info" | cut -d'|' -f1)
        local panes=$(echo "$info" | cut -d'|' -f2)
        local status=$(echo "$info" | cut -d'|' -f3)

        local status_color="${YELLOW}"
        local status_text="not active"
        if [ "$status" = "attached" ]; then
            status_color="${GREEN}"
            status_text="currently active"
        fi

        echo -e "  ${BLUE}$((i+1)).${NC} ${BOLD}$name${NC} - ${status_color}$status_text${NC}, $panes agent panes"
    done

    echo ""
    echo -e "${BLUE}What would you like to do? ${YELLOW}(Type a command and press Enter)${NC}"
    echo ""
    echo -e "  ${GREEN}a 1${NC}       - Attach to session #1"
    echo -e "  ${GREEN}a 1 2 3${NC}   - Attach to sessions #1, #2, #3 (opens each in new tab)"
    echo -e "  ${GREEN}k 2${NC}       - Kill session #2"
    echo -e "  ${GREEN}k 1 2 3${NC}   - Kill sessions #1, #2, #3"
    echo -e "  ${GREEN}k all${NC}     - Kill all sessions"
    echo -e "  ${GREEN}n${NC}         - Create a new session"
    echo -e "  ${GREEN}e${NC}         - Exit"
    echo ""
    echo -e "${YELLOW}💡 Type the full command (like 'a 1' or 'k 1 2 3'), not just a number!${NC}"
    echo ""
    echo -en "${GREEN}Your choice:${NC} "
    read choice || choice=""
    choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]' | xargs)

    case "$choice" in
        a\ *)
            # Extract all numbers from the command (handles "a 1 2 3" or "a 1,2,3")
            local nums=$(echo "$choice" | sed 's/^a //' | tr ',' ' ')
            local num_count=$(echo "$nums" | wc -w)

            # Single session - attach directly
            if [ "$num_count" -eq 1 ]; then
                local num=$nums
                if [ "$num" -ge 1 ] 2>/dev/null && [ "$num" -le "${#sessions[@]}" ]; then
                    local target_session="${sessions[$((num-1))]}"
                    echo -e "${GREEN}Attaching to session: $target_session${NC}"
                    log "User attached to existing session: $target_session"

                    # Sync scripts before attaching
                    sync_scripts_for_session "$target_session"

                    # Don't use exec - just attach normally
                    tmux attach -t "$target_session"

                    # If we get here, the session exited or user detached
                    # Automatically return to menu
                    echo ""
                    echo -e "${YELLOW}✓ Detached from session (agents still running in background)${NC}"
                    sleep 1
                    manage_existing_sessions
                    return $?
                else
                    echo -e "${RED}Invalid session number: $num${NC}"
                    sleep 1
                    manage_existing_sessions
                    return $?
                fi
            else
                # Multiple sessions - open each in new iTerm tab (if in iTerm) or sequentially
                local TERM_PROGRAM="${TERM_PROGRAM:-Terminal}"
                local invalid_nums=""
                local valid_sessions=()

                # Validate all session numbers first
                for num in $nums; do
                    if [ "$num" -ge 1 ] 2>/dev/null && [ "$num" -le "${#sessions[@]}" ]; then
                        valid_sessions+=("${sessions[$((num-1))]}")
                    else
                        invalid_nums="$invalid_nums $num"
                    fi
                done

                if [ -n "$invalid_nums" ]; then
                    echo -e "${RED}Invalid session number(s):$invalid_nums${NC}"
                    sleep 2
                fi

                if [ "${#valid_sessions[@]}" -eq 0 ]; then
                    echo -e "${RED}No valid sessions to attach${NC}"
                    sleep 1
                    manage_existing_sessions
                    return $?
                fi

                # Check if we're in iTerm2
                if [ "$TERM_PROGRAM" = "iTerm.app" ]; then
                    echo -e "${GREEN}Opening ${#valid_sessions[@]} sessions in new iTerm tabs...${NC}"
                    for session in "${valid_sessions[@]}"; do
                        echo -e "${BLUE}  Opening: $session${NC}"
                        osascript <<EOF
tell application "iTerm"
    tell current window
        create tab with default profile command "tmux attach -t $session"
    end tell
end tell
EOF
                        log "Opened session in new tab: $session"
                    done
                    echo -e "${GREEN}✓ Sessions opened in new tabs${NC}"
                    sleep 1
                else
                    echo -e "${YELLOW}Multiple session attach only works in iTerm2${NC}"
                    echo -e "${YELLOW}Attaching to first session only: ${valid_sessions[0]}${NC}"
                    sync_scripts_for_session "${valid_sessions[0]}"
                    tmux attach -t "${valid_sessions[0]}"
                fi

                manage_existing_sessions
                return $?
            fi
            ;;

        k\ *)
            # Extract all numbers from the command (handles "k 1 2 3" or "k 1,2,3")
            local nums=$(echo "$choice" | sed 's/^k //' | tr ',' ' ')

            # Handle "k all" specially
            if [ "$nums" = "all" ]; then
                echo -e "${YELLOW}Killing all sessions...${NC}"
                for session in "${sessions[@]}"; do
                    echo -e "${BLUE}  Killing: $session${NC}"
                    tmux kill-session -t "$session" 2>&1 || true
                    log "Killed session: $session"
                done
                echo -e "${GREEN}✓ All sessions killed${NC}"
                echo ""
                return 0
            fi

            # Kill multiple sessions
            local killed_any=false
            local invalid_nums=""
            for num in $nums; do
                if [ "$num" -ge 1 ] 2>/dev/null && [ "$num" -le "${#sessions[@]}" ]; then
                    local target_session="${sessions[$((num-1))]}"
                    echo -e "${YELLOW}Killing session #$num: $target_session${NC}"
                    tmux kill-session -t "$target_session" 2>&1 || true
                    log "Killed session: $target_session"
                    killed_any=true
                else
                    invalid_nums="$invalid_nums $num"
                fi
            done

            if [ "$killed_any" = true ]; then
                echo -e "${GREEN}✓ Session(s) killed${NC}"
            fi
            if [ -n "$invalid_nums" ]; then
                echo -e "${RED}Invalid session number(s):$invalid_nums${NC}"
            fi
            sleep 1
            manage_existing_sessions
            return $?
            ;;

        n|"")
            return 0
            ;;

        e)
            echo -e "${BLUE}Exiting${NC}"
            exit 0
            ;;

        *)
            echo ""
            echo -e "${RED}❌ Invalid choice: '$choice'${NC}"
            echo ""
            echo -e "${YELLOW}💡 You need to type the command, not just a number!${NC}"
            echo ""
            echo -e "${GREEN}Try one of these:${NC}"
            echo "  n         - Create new session"
            echo "  e         - Exit"
            echo "  a 1       - Attach to session #1"
            echo "  a 1 2 3   - Attach to multiple sessions (new tabs)"
            echo "  k 2       - Kill session #2"
            echo "  k 1 2 3   - Kill multiple sessions"
            echo "  k all     - Kill all sessions"
            echo ""
            sleep 3
            manage_existing_sessions
            return $?
            ;;
    esac
}

# Only show existing sessions menu if not coming from visual session manager
# (user already saw sessions there and chose to create new)
if [ "${SKIP_EXISTING_SESSIONS_CHECK:-0}" != "1" ]; then
    manage_existing_sessions
fi

check_duplicate_agent_names() {
    local phase="$1"
    local report
    report=$(tmux list-panes -a -F "#{session_name}:#{window_index}.#{pane_index}\t#{pane_current_path}\t#{@agent_name}" 2>/dev/null \
        | awk -F'\t' 'NF>=3 && $3!="" {print $3 "\t" $1 "\t" $2}' \
        | awk -F'\t' '{name=$1; pane=$2; path=$3; count[name]++; lines[name]=lines[name] "\n  - " pane " (" path ")"} END {for (name in count) if (count[name]>1) {print name lines[name] "\n"}}')

    if [ -n "$report" ]; then
        echo -e "${YELLOW}⚠️  Duplicate agent mail names detected ($phase):${NC}"
        echo "$report"
        return 1
    fi
    return 0
}

if ! check_duplicate_agent_names "before session creation"; then
    echo -en "${YELLOW}Continue anyway? [y/N]:${NC} "
    read dup_continue || dup_continue=""
    dup_continue=${dup_continue:-N}
    if ! [[ "$dup_continue" =~ ^[Yy]$ ]]; then
        log "User cancelled due to duplicate agent names"
        exit 1
    fi
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Multi-Agent Tmux Session Creator V2 (with tasks)          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if MCP Agent Mail server is running in Docker
echo -e "${BLUE}Checking MCP Agent Mail server...${NC}"
if docker ps | grep -q "8765.*8765"; then
    echo -e "${GREEN}✓ MCP server is running in Docker (port 8765)${NC}"
    log "MCP server detected on port 8765"
else
    echo -e "${YELLOW}⚠️  MCP server not detected on port 8765${NC}"
    echo -e "${YELLOW}   Agent mail features will not work${NC}"
    echo -e "${YELLOW}   Start it manually: cd \$MCP_AGENT_MAIL_DIR && docker-compose up -d${NC}"
    echo -e "${YELLOW}   (Default: ~/mcp_agent_mail)${NC}"
    log "WARNING: MCP server not detected"
fi
echo ""

# Prompt for session name (loop until resolved) - or use preset from visual manager
if [ -n "$PRESET_SESSION_NAME" ]; then
    SESSION_SAFE="$PRESET_SESSION_NAME"
    SESSION_NAME="$SESSION_SAFE"
    log "Using preset session name: $SESSION_NAME"
else
    while true; do
        echo -e "${BLUE}Give your multi-agent session a name (or press Enter for 'flywheel'):${NC}"
        echo -en "${YELLOW}Session name:${NC} "
        read SESSION_NAME || SESSION_NAME=""
        SESSION_NAME=${SESSION_NAME:-flywheel}
        SESSION_SAFE=$(echo "$SESSION_NAME" | tr -cs 'A-Za-z0-9_-' '_' | tr '[:upper:]' '[:lower:]' | sed 's/^_*//;s/_*$//')
        if [ -z "$SESSION_SAFE" ]; then
            echo -e "${RED}Error: Session name cannot be empty after sanitization${NC}"
            log "ERROR: Invalid session name provided"
            continue
        fi
        if [ "$SESSION_SAFE" != "$SESSION_NAME" ]; then
            echo -e "${YELLOW}Note: tmux session name normalized to '$SESSION_SAFE' from '$SESSION_NAME'${NC}"
            log "Session name normalized from $SESSION_NAME to $SESSION_SAFE"
        fi
        log "Session name: $SESSION_NAME (tmux: $SESSION_SAFE)"

    # Check if we're currently in the target session
    CURRENT_SESSION=$(tmux display-message -p '#S' 2>/dev/null || echo "")

    # Handle existing session as early as possible
    if tmux has-session -t "$SESSION_SAFE" 2>/dev/null; then
        if [ "$CURRENT_SESSION" = "$SESSION_SAFE" ]; then
            echo -e "${YELLOW}⚠️  You are currently in the '$SESSION_SAFE' session.${NC}"
            echo -e "${BLUE}Options:${NC}"
            echo -e "  ${GREEN}D${NC} - Detach and continue with this name"
            echo -e "  ${GREEN}N${NC} - Choose a new session name"
            echo -e "  ${GREEN}E${NC} - Exit"
            echo -en "${YELLOW}Choose [D/N/E]:${NC} "
            read session_choice || session_choice=""
            session_choice=${session_choice:-E}
            case "$session_choice" in
                [Dd])
                    tmux detach-client >/dev/null 2>&1 || true
                    log "Detached from session: $SESSION_SAFE"
                    break
                    ;;
                [Nn])
                    continue
                    ;;
                *)
                    log "User cancelled while in target session"
                    exit 1
                    ;;
            esac
        else
            echo -e "${YELLOW}Session '$SESSION_SAFE' already exists.${NC}"
            echo -e "${BLUE}Options:${NC}"
            echo -e "  ${GREEN}K${NC} - Kill existing session and recreate"
            echo -e "  ${GREEN}A${NC} - Attach to existing session"
            echo -e "  ${GREEN}N${NC} - Choose a new session name"
            echo -e "  ${GREEN}E${NC} - Exit"
            echo -en "${YELLOW}Choose [K/A/N/E]:${NC} "
            read session_choice || session_choice=""
            session_choice=${session_choice:-E}
            case "$session_choice" in
                [Kk])
                    echo -e "${YELLOW}🔄 Killing existing '$SESSION_SAFE' session...${NC}"
                    tmux kill-session -t "$SESSION_SAFE"
                    log "Killed existing session: $SESSION_NAME"
                    # Clean up old agent-name and pid files so fresh names are assigned
                    if [ -d "$PROJECT_PATH/pids" ]; then
                        for old_file in "$PROJECT_PATH/pids/${SESSION_SAFE}-"*.agent-name "$PROJECT_PATH/pids/${SESSION_SAFE}-"*.mail-monitor.pid; do
                            [ -f "$old_file" ] && rm -f "$old_file"
                        done
                        log "Cleaned up old agent files for killed session"
                    fi
                    break
                    ;;
                [Aa])
                    echo -e "${GREEN}Attaching to existing session...${NC}"
                    log "User chose to attach to existing session: $SESSION_SAFE"

                    # Sync scripts before attaching
                    sync_scripts_for_session "$SESSION_SAFE"

                    # Don't use exec - attach normally so we can handle exits
                    tmux attach -t "$SESSION_SAFE"

                    # If we return here, session was detached or exited
                    echo ""
                    echo -e "${YELLOW}Session detached or exited.${NC}"
                    echo -e "${BLUE}What would you like to do?${NC}"
                    echo -e "  ${GREEN}R${NC} - Return to choose/create session"
                    echo -e "  ${GREEN}E${NC} - Exit"
                    echo -en "${YELLOW}Choose [R/E]:${NC} "
                    read post_attach_action || post_attach_action=""
                    post_attach_action=${post_attach_action:-E}

                    if [[ "$post_attach_action" =~ ^[Rr]$ ]]; then
                        continue
                    else
                        exit 0
                    fi
                    ;;
                [Nn])
                    continue
                    ;;
                *)
                    log "User cancelled - existing session kept"
                    exit 1
                    ;;
            esac
        fi
    else
        break
    fi
    done
fi

# Prompt for project path (no directory scanning - fully portable)
echo ""
# Check if project path was provided via environment variable (from file picker)
if [ -n "${SELECTED_PROJECT_PATH:-}" ]; then
    PROJECT_PATH="$SELECTED_PROJECT_PATH"
    echo -e "${GREEN}Using selected project: ${PROJECT_PATH/#$HOME/\~}${NC}"
    log "Using selected project path: $PROJECT_PATH"
else
    echo -e "${BLUE}Project Directory:${NC}"
    echo -e "${BLUE}Tip: Paths with spaces are OK - quotes will be handled automatically${NC}"
    echo -en "${YELLOW}Enter project path [press Enter for current directory]:${NC} "
    read PROJECT_PATH || PROJECT_PATH=""

    # Use current directory if not specified
    if [ -z "$PROJECT_PATH" ]; then
        PROJECT_PATH="$(pwd)"
        echo -e "${GREEN}Using current directory: ${PROJECT_PATH/#$HOME/\~}${NC}"
        log "Using current directory: $PROJECT_PATH"
    fi
fi

# Process the path (strip quotes, expand ~, etc.)
if [ -n "$PROJECT_PATH" ] && [ "$PROJECT_PATH" != "$(pwd)" ]; then
    # Strip leading/trailing quotes (handles 'path' or "path")
    PROJECT_PATH="${PROJECT_PATH#\'}"
    PROJECT_PATH="${PROJECT_PATH%\'}"
    PROJECT_PATH="${PROJECT_PATH#\"}"
    PROJECT_PATH="${PROJECT_PATH%\"}"

    # Trim whitespace
    PROJECT_PATH=$(echo "$PROJECT_PATH" | xargs)

    # Expand ~ to home directory
    PROJECT_PATH="${PROJECT_PATH/#\~/$HOME}"

    # Create directory if it doesn't exist
    if [ ! -d "$PROJECT_PATH" ]; then
        echo -e "${YELLOW}Warning: Directory $PROJECT_PATH does not exist.${NC}"
        read -p "Create it? (y/n): " CREATE_DIR || CREATE_DIR="n"
        if [ "$CREATE_DIR" = "y" ] || [ "$CREATE_DIR" = "Y" ]; then
            mkdir -p "$PROJECT_PATH"
            echo -e "${GREEN}✓ Created directory${NC}"
            log "Created directory: $PROJECT_PATH"
        else
            echo "Exiting..."
            log "User cancelled - directory creation declined"
            exit 1
        fi
    fi
    echo -e "${GREEN}Using: ${PROJECT_PATH/#$HOME/\~}${NC}"
    log "Using project path: $PROJECT_PATH"
fi

# Source shared project configuration if available (after PROJECT_PATH is set)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/project-config.sh" ]; then
    export PROJECT_ROOT="$PROJECT_PATH"
    source "$SCRIPT_DIR/lib/project-config.sh"
    log "Sourced project-config.sh"
fi

echo -e "${BLUE}Ensuring agent mail helpers are available in project...${NC}"
ensure_mail_scripts_available

echo -e "${BLUE}Creating agent mail documentation...${NC}"
create_agent_mail_docs

echo -e "${BLUE}Syncing AGENTS.md workflow documentation...${NC}"
sync_agents_md

echo -e "${BLUE}Updating CLAUDE.md references...${NC}"
update_claude_md_reference

# Prompt for number of agents - or use presets from visual manager
if [ -n "$PRESET_CLAUDE_COUNT" ]; then
    CLAUDE_COUNT="$PRESET_CLAUDE_COUNT"
    CHATGPT_COUNT="${PRESET_CHATGPT_COUNT:-0}"
    CODEX_COUNT="${PRESET_CODEX_COUNT:-0}"
    DEEPSEEK_COUNT="${PRESET_DEEPSEEK_COUNT:-0}"
    GROK_COUNT="${PRESET_GROK_COUNT:-0}"
    log "Using preset agent counts - Claude: $CLAUDE_COUNT, ChatGPT: $CHATGPT_COUNT, Codex: $CODEX_COUNT, DeepSeek: $DEEPSEEK_COUNT, Grok: $GROK_COUNT"
else
    # Prompt for number of agents
    echo ""
    echo -e "${BLUE}How many AI coding agents do you want?${NC}"
    echo -e "${YELLOW}💡 Tip: Start with 2 Claude agents if you're not sure${NC}"
    echo ""
    echo -en "${YELLOW}Number of Claude agents (press Enter for 2):${NC} "
    read CLAUDE_COUNT || CLAUDE_COUNT=""
    CLAUDE_COUNT=${CLAUDE_COUNT:-2}

    echo -en "${YELLOW}Number of ChatGPT agents via OAuth (press Enter for 0):${NC} "
    read CHATGPT_COUNT || CHATGPT_COUNT=""
    CHATGPT_COUNT=${CHATGPT_COUNT:-0}

    echo -en "${YELLOW}Number of Codex agents (press Enter for 0):${NC} "
    read CODEX_COUNT || CODEX_COUNT=""
    CODEX_COUNT=${CODEX_COUNT:-0}

    echo -en "${YELLOW}Number of DeepSeek agents (press Enter for 0):${NC} "
    read DEEPSEEK_COUNT || DEEPSEEK_COUNT=""
    DEEPSEEK_COUNT=${DEEPSEEK_COUNT:-0}

    echo -en "${YELLOW}Number of Grok agents (press Enter for 0):${NC} "
    read GROK_COUNT || GROK_COUNT=""
    GROK_COUNT=${GROK_COUNT:-0}
fi

# Prompt for shared task list - or use preset
if [ -n "$PRESET_ENABLE_SHARED_TASKS" ]; then
    ENABLE_SHARED_TASKS="$PRESET_ENABLE_SHARED_TASKS"
    TASK_LIST_ID="$PRESET_TASK_LIST_ID"
    if [[ "$ENABLE_SHARED_TASKS" =~ ^[Yy]$ ]]; then
        log "Using preset shared task list: $TASK_LIST_ID"
    else
        log "Using preset: Individual task lists"
    fi
else
    # NEW: Prompt for shared task list
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Shared Task List Configuration (NEW)                         ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Shared task lists allow all agents to see and collaborate on the same tasks.${NC}"
    echo -e "${YELLOW}Without this, each agent has its own separate task list.${NC}"
    echo ""
    echo -en "${YELLOW}Enable shared task list for all agents? [y/N]:${NC} "
    read ENABLE_SHARED_TASKS || ENABLE_SHARED_TASKS=""
    ENABLE_SHARED_TASKS=${ENABLE_SHARED_TASKS:-N}

    TASK_LIST_ID=""
    if [[ "$ENABLE_SHARED_TASKS" =~ ^[Yy] ]]; then
        echo -en "${YELLOW}Task list ID [default: $SESSION_SAFE-tasks]:${NC} "
        read TASK_LIST_ID || TASK_LIST_ID=""
        TASK_LIST_ID=${TASK_LIST_ID:-"$SESSION_SAFE-tasks"}
        echo -e "${GREEN}✓ Shared task list enabled: $TASK_LIST_ID${NC}"
        log "Shared task list enabled: $TASK_LIST_ID"
    else
        echo -e "${BLUE}Each agent will have its own task list${NC}"
        log "Shared task list disabled"
    fi
    echo ""
fi

# Validate counts
if ! [[ "$CLAUDE_COUNT" =~ ^[0-9]+$ ]] || ! [[ "$CODEX_COUNT" =~ ^[0-9]+$ ]]; then
    echo "Error: Agent counts must be numbers"
    log "ERROR: Invalid agent counts - Claude: $CLAUDE_COUNT, Codex: $CODEX_COUNT"
    exit 1
fi

TOTAL_AGENTS=$((CLAUDE_COUNT + CHATGPT_COUNT + CODEX_COUNT + DEEPSEEK_COUNT + GROK_COUNT))
log "Agent counts - Claude: $CLAUDE_COUNT, ChatGPT: $CHATGPT_COUNT, Codex: $CODEX_COUNT, DeepSeek: $DEEPSEEK_COUNT, Grok: $GROK_COUNT, Total: $TOTAL_AGENTS"

if [ "$TOTAL_AGENTS" -eq 0 ]; then
    echo "Error: Must have at least one agent"
    log "ERROR: No agents specified"
    exit 1
fi

if [ "$TOTAL_AGENTS" -gt "$MAX_AGENTS_WARNING" ]; then
    echo -e "${YELLOW}Warning: $TOTAL_AGENTS agents will create many panes. Consider using fewer.${NC}"
    read -p "Continue? (y/n): " CONTINUE || CONTINUE="n"
    if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
        log "User cancelled - too many agents"
        exit 0
    fi
fi

# Authentication setup for non-Claude agents
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Authentication Setup${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ "$CHATGPT_COUNT" -gt 0 ]; then
    if [ ! -f "$HOME/.codex/auth.json" ]; then
        echo -e "${YELLOW}ChatGPT agents require browser authentication${NC}"
        echo -en "${YELLOW}Run ChatGPT setup now? [Y/n]:${NC} "
        read setup_chatgpt || setup_chatgpt=""
        setup_chatgpt=${setup_chatgpt:-Y}

        if [[ "$setup_chatgpt" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}Running ChatGPT setup (will open browser)...${NC}"
            "$SCRIPT_DIR/setup-chatgpt.sh"
            echo ""
        else
            echo -e "${RED}Warning: ChatGPT agents will fail without authentication${NC}"
            echo ""
        fi
    else
        echo -e "${GREEN}✓ ChatGPT authentication already configured${NC}"
    fi
fi

if [ "$DEEPSEEK_COUNT" -gt 0 ]; then
    if [ -z "${DEEPSEEK_API_KEY:-}" ]; then
        echo -e "${YELLOW}DeepSeek agents require API key${NC}"
        echo -en "${YELLOW}Run DeepSeek setup now? [Y/n]:${NC} "
        read setup_deepseek || setup_deepseek=""
        setup_deepseek=${setup_deepseek:-Y}

        if [[ "$setup_deepseek" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}Running DeepSeek setup...${NC}"
            "$SCRIPT_DIR/setup-deepseek.sh"
            # Source the shell RC to get the new API key
            if [ -f "$HOME/.zshrc" ]; then
                source "$HOME/.zshrc"
            elif [ -f "$HOME/.bashrc" ]; then
                source "$HOME/.bashrc"
            fi
            echo ""
        else
            echo -e "${RED}Warning: DeepSeek agents will fail without API key${NC}"
            echo ""
        fi
    else
        echo -e "${GREEN}✓ DeepSeek API key already configured${NC}"
    fi
fi

if [ "$GROK_COUNT" -gt 0 ]; then
    if [ -z "${XAI_API_KEY:-}" ]; then
        echo -e "${YELLOW}Grok agents require xAI API key${NC}"
        echo -en "${YELLOW}Run Grok setup now? [Y/n]:${NC} "
        read setup_grok || setup_grok=""
        setup_grok=${setup_grok:-Y}

        if [[ "$setup_grok" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}Running Grok setup...${NC}"
            "$SCRIPT_DIR/setup-grok.sh"
            # Source the shell RC to get the new API key
            if [ -f "$HOME/.zshrc" ]; then
                source "$HOME/.zshrc"
            elif [ -f "$HOME/.bashrc" ]; then
                source "$HOME/.bashrc"
            fi
            echo ""
        else
            echo -e "${RED}Warning: Grok agents will fail without API key${NC}"
            echo ""
        fi
    else
        echo -e "${GREEN}✓ xAI API key already configured${NC}"
    fi
fi

echo ""

# (Session existence handled earlier, right after name selection.)

# Create new session
# Ensure project has tmux config, copy from agent-flywheel if needed
TMUX_CONFIG="$PROJECT_PATH/.tmux.conf.agentcore"
SOURCE_CONFIG="$AGENTCORE_ROOT/.tmux.conf.agentcore"

if [ ! -f "$TMUX_CONFIG" ]; then
    echo -e "${YELLOW}Installing tmux config to project...${NC}"
    cp "$SOURCE_CONFIG" "$TMUX_CONFIG"
    log "Copied tmux config to project: $TMUX_CONFIG"
fi

echo -e "${GREEN}🚀 Creating tmux session '$SESSION_NAME'...${NC}"
tmux -f "$TMUX_CONFIG" new-session -d -s "$SESSION_SAFE" -c "$PROJECT_PATH"
log "Created session: $SESSION_NAME"

# Set iTerm tab title to project name
PROJECT_NAME=$(basename "$PROJECT_PATH")
printf "\033]0;%s\007" "$PROJECT_NAME"

# Apply tmux configuration (session-scoped where possible)
tmux set -t "$SESSION_SAFE" base-index 1
tmux set -t "$SESSION_SAFE" pane-base-index 1
tmux set -t "$SESSION_SAFE" pane-border-status top
tmux set -t "$SESSION_SAFE" pane-border-format '#[fg=cyan]#{@llm_name}#[fg=default] #[fg=green]#{@agent_name}#[align=right]#[fg=yellow]#([ -f "#{pane_current_path}/.claude-hooks-bypass" ] && echo "⚠️ Bypass: $(basename "#{pane_current_path}")" || echo "")'
tmux set -g mouse on
tmux set -g status-interval 5
tmux set -t "$SESSION_SAFE" history-limit "$HISTORY_LIMIT"
log "Applied tmux configuration"

# Auto-rearrange grid and cleanup when pane is closed/killed (SESSION-SPECIFIC)
tmux set-hook -t "$SESSION_SAFE" after-kill-pane "run-shell \"tmux select-layout -t #{session_name}:#{window_index} tiled 2>/dev/null; bash $AGENTCORE_ROOT/scripts/cleanup-after-pane-removal.sh #{session_name} 2>/dev/null || true\""

# Rename first window
tmux rename-window -t "$SESSION_SAFE:1" "agents"

# Split window into required panes
for ((i=2; i<=TOTAL_AGENTS; i++)); do
    if [ $i -eq 2 ]; then
        # First split - vertical
        tmux split-window -h -c "$PROJECT_PATH" -t "$SESSION_SAFE:1"
    elif [ $((i % 2)) -eq 1 ]; then
        # Odd panes (3,5,7...) - split the left side
        tmux split-window -v -c "$PROJECT_PATH" -t "$SESSION_SAFE:1.$(((i-1)/2))"
    else
        # Even panes (4,6,8...) - split the right side
        tmux split-window -v -c "$PROJECT_PATH" -t "$SESSION_SAFE:1.$((i/2))"
    fi
done
log "Created $TOTAL_AGENTS panes"

# CRITICAL FIX #2: Capture actual pane IDs after creation
echo -e "${GREEN}Capturing actual pane IDs...${NC}"
PANE_IDS=()
while IFS= read -r pane_id; do
    PANE_IDS+=("$pane_id")
done < <(tmux list-panes -t "$SESSION_SAFE:1" -F "#{pane_index}" | sort -n)
log "Captured pane IDs: ${PANE_IDS[*]}"

if [ ${#PANE_IDS[@]} -ne "$TOTAL_AGENTS" ]; then
    echo -e "${RED}ERROR: Expected $TOTAL_AGENTS panes but found ${#PANE_IDS[@]}${NC}"
    log "ERROR: Pane count mismatch - expected $TOTAL_AGENTS, got ${#PANE_IDS[@]}"
    exit 1
fi

# Cleanup ALL agent-name, pid, and identity files for this session
# Fresh session = fresh names. Old files would cause name reuse because
# auto-register-agent.sh skips registration when an agent-name file exists,
# and discover.sh skips registration when identity has agent_mail_name.
echo -e "${GREEN}Cleaning up agent files for session...${NC}"
ARCHIVE_PIDS_DIR="$PROJECT_PATH/archive/pids"
mkdir -p "$ARCHIVE_PIDS_DIR"
for file in "$PROJECT_PATH/pids/${SESSION_SAFE}-"*.agent-name "$PROJECT_PATH/pids/${SESSION_SAFE}-"*.mail-monitor.pid; do
    [ -f "$file" ] || continue
    base_name=$(basename "$file")
    mv "$file" "$ARCHIVE_PIDS_DIR/"
    log "Archived old session file: $base_name"
done
# Also clean up pane identity files (contain agent_mail_name from previous session)
if [ -d "$PROJECT_PATH/panes" ]; then
    for file in "$PROJECT_PATH/panes/${SESSION_SAFE}-"*.identity; do
        [ -f "$file" ] || continue
        base_name=$(basename "$file")
        mv "$file" "$ARCHIVE_PIDS_DIR/"
        log "Archived old identity file: $base_name"
    done
fi

# Set up Claude agents using actual pane IDs
echo -e "${GREEN}Starting $CLAUDE_COUNT Claude agents...${NC}"
for ((i=0; i<CLAUDE_COUNT; i++)); do
    PANE_NUM=${PANE_IDS[$i]}
    PANE="$SESSION_SAFE:1.$PANE_NUM"
    # Set custom tmux variables for labels (1-indexed for display)
    tmux set -p -t "$PANE" @llm_name "Claude $((i+1))"

    # Build export command with optional CLAUDE_CODE_TASK_LIST_ID
    EXPORT_CMD="export PROJECT_ROOT='$PROJECT_PATH' MAIL_PROJECT_KEY='$PROJECT_PATH'"
    if [ -n "$TASK_LIST_ID" ]; then
        EXPORT_CMD="$EXPORT_CMD CLAUDE_CODE_TASK_LIST_ID='$TASK_LIST_ID'"
        log "Starting Claude agent $((i+1)) with shared task list: $TASK_LIST_ID"
    fi

    # Launch Claude (mail monitors start after registration — see post-registration block)
    tmux send-keys -t "$PANE" "$EXPORT_CMD && claude --dangerously-skip-permissions" C-m
    log "Started Claude agent $((i+1)) in pane $PANE_NUM"
done

# Set up Codex (Qodo) agents using actual pane IDs
echo -e "${GREEN}Starting $CODEX_COUNT Codex agents...${NC}"
for ((i=0; i<CODEX_COUNT; i++)); do
    PANE_INDEX=$((CLAUDE_COUNT + i))
    PANE_NUM=${PANE_IDS[$PANE_INDEX]}
    PANE="$SESSION_SAFE:1.$PANE_NUM"
    # Set custom tmux variables for labels (1-indexed for display)
    tmux set -p -t "$PANE" @llm_name "Codex $((i+1))"

    # Build export command (Codex doesn't use task lists, but include for consistency)
    EXPORT_CMD="export PROJECT_ROOT='$PROJECT_PATH' MAIL_PROJECT_KEY='$PROJECT_PATH'"

    # Launch Codex (mail monitors start after registration)
    tmux send-keys -t "$PANE" "$EXPORT_CMD && cd \"$PROJECT_PATH\" && codex --dangerously-bypass-approvals-and-sandbox" C-m
    log "Started Codex agent $((i+1)) in pane $PANE_NUM"
done

# Set up ChatGPT agents using actual pane IDs
echo -e "${GREEN}Starting $CHATGPT_COUNT ChatGPT agents...${NC}"
for ((i=0; i<CHATGPT_COUNT; i++)); do
    PANE_INDEX=$((CLAUDE_COUNT + CODEX_COUNT + i))
    PANE_NUM=${PANE_IDS[$PANE_INDEX]}
    PANE="$SESSION_SAFE:1.$PANE_NUM"
    # Set custom tmux variables for labels (1-indexed for display)
    tmux set -p -t "$PANE" @llm_name "ChatGPT $((i+1))"

    # Build export command
    EXPORT_CMD="export PROJECT_ROOT='$PROJECT_PATH' MAIL_PROJECT_KEY='$PROJECT_PATH'"

    # Launch ChatGPT agent (mail monitors start after registration)
    tmux send-keys -t "$PANE" "$EXPORT_CMD && cd \"$PROJECT_PATH\" && codex" C-m
    log "Started ChatGPT agent $((i+1)) in pane $PANE_NUM"
done

# Set up DeepSeek agents using actual pane IDs
echo -e "${GREEN}Starting $DEEPSEEK_COUNT DeepSeek agents...${NC}"
for ((i=0; i<DEEPSEEK_COUNT; i++)); do
    PANE_INDEX=$((CLAUDE_COUNT + CODEX_COUNT + CHATGPT_COUNT + i))
    PANE_NUM=${PANE_IDS[$PANE_INDEX]}
    PANE="$SESSION_SAFE:1.$PANE_NUM"
    # Set custom tmux variables for labels (1-indexed for display)
    tmux set -p -t "$PANE" @llm_name "DeepSeek $((i+1))"

    # Build export command
    EXPORT_CMD="export PROJECT_ROOT='$PROJECT_PATH' MAIL_PROJECT_KEY='$PROJECT_PATH'"
    if [ -n "${DEEPSEEK_API_KEY:-}" ]; then
        EXPORT_CMD="$EXPORT_CMD DEEPSEEK_API_KEY='$DEEPSEEK_API_KEY'"
    fi

    # Launch DeepSeek (mail monitors start after registration)
    tmux send-keys -t "$PANE" "$EXPORT_CMD && cd \"$PROJECT_PATH\" && ./scripts/deepseek-claude-wrapper.sh" C-m
    log "Started DeepSeek agent $((i+1)) in pane $PANE_NUM"
done

# Set up Grok agents using actual pane IDs
echo -e "${GREEN}Starting $GROK_COUNT Grok agents...${NC}"
for ((i=0; i<GROK_COUNT; i++)); do
    PANE_INDEX=$((CLAUDE_COUNT + CODEX_COUNT + CHATGPT_COUNT + DEEPSEEK_COUNT + i))
    PANE_NUM=${PANE_IDS[$PANE_INDEX]}
    PANE="$SESSION_SAFE:1.$PANE_NUM"
    # Set custom tmux variables for labels (1-indexed for display)
    tmux set -p -t "$PANE" @llm_name "Grok $((i+1))"

    # Build export command
    EXPORT_CMD="export PROJECT_ROOT='$PROJECT_PATH' MAIL_PROJECT_KEY='$PROJECT_PATH'"
    if [ -n "${XAI_API_KEY:-}" ]; then
        EXPORT_CMD="$EXPORT_CMD XAI_API_KEY='$XAI_API_KEY'"
    fi

    # Launch Grok (mail monitors start after registration)
    tmux send-keys -t "$PANE" "$EXPORT_CMD && cd \"$PROJECT_PATH\" && ./scripts/grok-claude-wrapper.sh" C-m
    log "Started Grok agent $((i+1)) in pane $PANE_NUM"
done

# Auto-register all agents with mail system
echo -e "${GREEN}Registering agents with mail system...${NC}"
log "Waiting ${AGENT_INIT_WAIT}s for agents to initialize"
sleep "$AGENT_INIT_WAIT"

# Register only the panes in this session (not --all, which would affect other sessions)
for ((i=0; i<TOTAL_AGENTS; i++)); do
    PANE_NUM=${PANE_IDS[$i]}
    PANE_ID="$SESSION_SAFE:1.$PANE_NUM"

    if ! PROJECT_ROOT="$PROJECT_PATH" bash "$FLYWHEEL_DIR/panes/discover.sh" --pane "$PANE_ID" --quiet; then
        echo -e "${YELLOW}Warning: Could not register pane $PANE_ID${NC}"
        log "WARNING: Agent registration failed for $PANE_ID"
    fi
done
log "Successfully registered agents"

# Allow time for registration files to settle (Part C: Session Init Fix)
echo -e "${GREEN}Waiting for registration to settle...${NC}"
log "Waiting ${REGISTRATION_SETTLE_WAIT}s for registration files to settle"
sleep "$REGISTRATION_SETTLE_WAIT"

# Check for duplicates after registration (names are assigned by mail server)
if ! check_duplicate_agent_names "after registration"; then
    echo -e "${YELLOW}Note: duplicates can be caused by other active/detached sessions with the same agent names.${NC}"
    log "Duplicate agent names detected after registration"
fi

# Explicitly set tmux @agent_name variables from registered agent names
for ((i=0; i<TOTAL_AGENTS; i++)); do
    PANE_NUM=${PANE_IDS[$i]}
    PANE_ID="$SESSION_SAFE:1.$PANE_NUM"
    SAFE_PANE=$(echo "$PANE_ID" | tr ':.' '-')
    AGENT_NAME_FILE="$PROJECT_PATH/pids/${SAFE_PANE}.agent-name"

    if [ -f "$AGENT_NAME_FILE" ]; then
        AGENT_NAME=$(cat "$AGENT_NAME_FILE")
        tmux set-option -p -t "$PANE_ID" @agent_name "$AGENT_NAME" 2>/dev/null || true
        log "Set @agent_name=$AGENT_NAME for pane $PANE_ID"
    fi
done

# Start mail monitors for all agents (AFTER registration so agent-name files exist)
# Set TMUX_PANE explicitly so monitors can target the correct pane from outside.
echo -e "${GREEN}Starting mail monitors for agents...${NC}"
MONITOR_FAILURES=0
for ((i=0; i<TOTAL_AGENTS; i++)); do
    PANE_NUM=${PANE_IDS[$i]}
    PANE_ID="$SESSION_SAFE:1.$PANE_NUM"
    SAFE_PANE=$(echo "$PANE_ID" | tr ':.' '-')
    AGENT_NAME_FILE="$PROJECT_PATH/pids/${SAFE_PANE}.agent-name"

    if [ -f "$AGENT_NAME_FILE" ]; then
        AGENT_NAME=$(cat "$AGENT_NAME_FILE")
        # Get the actual tmux pane ID (e.g., %235) so the monitor can target it
        ACTUAL_PANE_ID=$(tmux display-message -t "$PANE_ID" -p "#{pane_id}" 2>/dev/null || echo "")
        if [ -z "$ACTUAL_PANE_ID" ]; then
            echo -e "${YELLOW}Warning: Could not get pane ID for $PANE_ID${NC}"
            log "WARNING: tmux display-message failed for $PANE_ID"
            MONITOR_FAILURES=$((MONITOR_FAILURES + 1))
            continue
        fi

        log "Starting mail monitor for $AGENT_NAME (pane $PANE_ID, tmux $ACTUAL_PANE_ID)"

        # Launch monitor with explicit TMUX_PANE and MONITOR_SAFE_PANE
        # so it can inject notifications into the correct pane from outside
        MONITOR_OUTPUT=$(TMUX_PANE="$ACTUAL_PANE_ID" \
            MONITOR_SAFE_PANE="$SAFE_PANE" \
            AGENT_NAME="$AGENT_NAME" \
            PROJECT_ROOT="$PROJECT_PATH" \
            MAIL_PROJECT_KEY="$PROJECT_PATH" \
            "$PROJECT_PATH/scripts/mail-monitor-ctl.sh" --pane "$PANE_ID" start 2>&1) || true

        # Check if monitor actually started
        MONITOR_PID_FILE="$PROJECT_PATH/pids/${SAFE_PANE}.mail-monitor.pid"
        if [ -f "$MONITOR_PID_FILE" ]; then
            MONITOR_PID=$(cat "$MONITOR_PID_FILE")
            if ps -p "$MONITOR_PID" > /dev/null 2>&1; then
                log "Mail monitor started for $AGENT_NAME (PID: $MONITOR_PID)"
            else
                echo -e "${YELLOW}Warning: Monitor for $AGENT_NAME started but died immediately${NC}"
                log "WARNING: Monitor died for $AGENT_NAME. Output: $MONITOR_OUTPUT"
                MONITOR_FAILURES=$((MONITOR_FAILURES + 1))
            fi
        else
            echo -e "${YELLOW}Warning: Monitor failed to start for $AGENT_NAME${NC}"
            log "WARNING: No PID file for $AGENT_NAME. Output: $MONITOR_OUTPUT"
            MONITOR_FAILURES=$((MONITOR_FAILURES + 1))
        fi
    else
        echo -e "${YELLOW}Warning: No agent name file for pane $PANE_NUM — cannot start monitor${NC}"
        log "WARNING: Missing agent name file: $AGENT_NAME_FILE"
        MONITOR_FAILURES=$((MONITOR_FAILURES + 1))
    fi
done

if [ "$MONITOR_FAILURES" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  $MONITOR_FAILURES monitor(s) failed to start (check log: $LOG_FILE)${NC}"
    log "WARNING: $MONITOR_FAILURES monitor(s) failed to start"
else
    echo -e "${GREEN}✅ All mail monitors started successfully${NC}"
    log "All mail monitors started"
fi

# Run validation on all panes (Part C: Session Init Fix)
echo -e "${GREEN}Validating agent setup...${NC}"
VALIDATION_FAILED=0
for ((i=0; i<TOTAL_AGENTS; i++)); do
    PANE_NUM=${PANE_IDS[$i]}
    PANE_ID="$SESSION_SAFE:1.$PANE_NUM"
    SAFE_PANE=$(echo "$PANE_ID" | tr ':.' '-')
    AGENT_NAME_FILE="$PROJECT_PATH/pids/${SAFE_PANE}.agent-name"

    if [ -f "$AGENT_NAME_FILE" ]; then
        AGENT_NAME=$(cat "$AGENT_NAME_FILE")
        log "Validating $AGENT_NAME (pane $PANE_ID)"

        if [ -f "$PROJECT_PATH/scripts/validate-agent-session.sh" ]; then
            if ! (cd "$PROJECT_PATH" && bash "$PROJECT_PATH/scripts/validate-agent-session.sh" "$PANE_ID" "$AGENT_NAME" 2>&1 | tee -a "$LOG_FILE"); then
                echo -e "${YELLOW}Warning: Validation issues for $AGENT_NAME${NC}"
                VALIDATION_FAILED=$((VALIDATION_FAILED + 1))
            fi
        fi
    fi
done

if [ "$VALIDATION_FAILED" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  $VALIDATION_FAILED agent(s) had validation warnings (check log: $LOG_FILE)${NC}"
    log "WARNING: $VALIDATION_FAILED agent(s) failed validation"
else
    echo -e "${GREEN}✅ All agents validated successfully${NC}"
    log "All agents passed validation"
fi

# Start bead-stale-monitor (auto-notify for stale beads)
if [ -f "$PROJECT_PATH/scripts/bead-stale-monitor.sh" ]; then
    if ! "$PROJECT_PATH/scripts/bead-stale-monitor.sh" status >/dev/null 2>&1; then
        echo -e "${GREEN}Starting bead stale monitor...${NC}"
        log "Starting bead-stale-monitor"
        "$PROJECT_PATH/scripts/bead-stale-monitor.sh" start >/dev/null 2>&1 || true
        if "$PROJECT_PATH/scripts/bead-stale-monitor.sh" status >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Bead monitor started${NC}"
            log "Bead monitor started successfully"
        else
            echo -e "${YELLOW}⚠️  Warning: Bead monitor may not have started${NC}"
            log "WARNING: Bead monitor start verification failed"
        fi
    else
        echo -e "${GREEN}✅ Bead monitor already running${NC}"
        log "Bead monitor already running"
    fi
fi

# Balance pane layout
tmux select-layout -t "$SESSION_SAFE:1" tiled
log "Applied tiled layout"

# Select first pane
tmux select-pane -t "$SESSION_SAFE:1.${PANE_IDS[0]}"

# Create bead viewer window
echo -e "${GREEN}Creating bead viewer window...${NC}"
log "Creating bead viewer window"
tmux new-window -t "$SESSION_SAFE:2" -n "bead-viewer" -c "$PROJECT_PATH"
tmux send-keys -t "$SESSION_SAFE:2" "bv" C-m
log "Bead viewer started in window 2"

# Switch back to agents window
tmux select-window -t "$SESSION_SAFE:1"
log "Switched back to agents window"

echo ""
echo -e "${GREEN}✅ Tmux session created successfully!${NC}"
echo ""
echo -e "${BLUE}📋 Session Info:${NC}"
echo "   Session: $SESSION_NAME"
echo "   Total agents: $TOTAL_AGENTS ($CLAUDE_COUNT Claude + $CODEX_COUNT Codex)"
echo "   Working directory: $PROJECT_PATH"
echo -e "   ${CYAN}Bead Viewer: Window 2 (Ctrl+b, then 2)${NC}"
if [ -n "$TASK_LIST_ID" ]; then
    echo -e "   ${GREEN}Shared task list: $TASK_LIST_ID${NC}"
fi
echo "   Log file: $LOG_FILE"
echo ""
echo -e "${BLUE}🎮 Tmux Keyboard Shortcuts (for beginners):${NC}"
echo ""
echo -e "  ${GREEN}Essential:${NC}"
echo "   Ctrl+b, then arrow keys  - Switch between panes"
echo "   Ctrl+b, then d           - Detach (exit without closing)"
echo "   Ctrl+b, then 2           - Switch to bead viewer window"
echo "   Ctrl+b, then 1           - Switch back to agents window"
echo ""
echo -e "  ${GREEN}Helpful:${NC}"
echo "   Ctrl+b, then q           - Show pane numbers"
echo "   Ctrl+b, then z           - Zoom current pane (toggle fullscreen)"
echo "   Ctrl+b, then x           - Close current pane (asks for confirmation)"
echo ""
echo -e "  ${GREEN}To reattach later:${NC}"
echo "   tmux attach -t $SESSION_NAME"
echo ""
echo -e "${YELLOW}💡 Tip: Press Ctrl+b, release, THEN press the next key${NC}"
echo ""
echo -e "${GREEN}Attaching to session...${NC}"

# Verify session exists before attaching
if ! tmux has-session -t "$SESSION_SAFE" 2>/dev/null; then
    echo -e "${RED}ERROR: Session '$SESSION_NAME' was not created successfully${NC}"
    log "ERROR: Session verification failed"
    read -p "Press Enter to close..." dummy || true
    exit 1
fi

# Check if we're already in tmux
if [ -n "$TMUX" ]; then
    echo -e "${YELLOW}⚠️  You're already in a tmux session${NC}"
    echo -e "${BLUE}To switch to the new session, use:${NC}"
    echo -e "${GREEN}  tmux switch-client -t $SESSION_SAFE${NC}"
    echo ""
    echo -e "${BLUE}Or detach first and attach manually:${NC}"
    echo -e "${GREEN}  Ctrl+b, d  (detach)${NC}"
    echo -e "${GREEN}  tmux attach -t $SESSION_SAFE${NC}"
    log "Session created - switching client"; tmux switch-client -t "$SESSION_SAFE"
else
    # Not in tmux, safe to attach
    echo -e "${GREEN}Attaching to session...${NC}"
    echo -e "${YELLOW}💡 Remember: Press 'Ctrl+b' first, release, then press 'd' to detach${NC}"
    log "Session creation complete - attaching"
    sleep 2
    exec tmux attach -t "$SESSION_SAFE"
fi
