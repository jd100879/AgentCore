# Agent Workflow Tools

Core automation and coordination tools for multi-agent development workflows.

## Overview

This toolkit enables autonomous agent execution, multi-agent coordination via MCP Agent Mail, task management integration with beads, and real-time communication monitoring.

## Installation

```bash
cd ~/Projects/AgentCore/tools/agent_workflow
./install.sh
```

Installs to:
- `~/.local/bin/` - All executable commands
- `~/.local/lib/agent_workflow/` - Shared library files

## Core Workflow Tools

### agent-runner
Autonomous agent execution loop with automatic work assignment.

```bash
agent-runner [bead-id]
```

Features:
- Launches Claude Code with pre-assigned bead
- Auto-registers with MCP Agent Mail
- Monitors for new mail and tasks
- Cleans up on exit

### visual-session-manager
fzf-based interactive tmux session launcher.

```bash
visual-session-manager
```

Features:
- Create/kill/resurrect/attach sessions
- Visual feedback with preview pane
- Auto-syncs scripts to project directories
- Session discovery and management

### agent-mail-helper
MCP Agent Mail client wrapper.

```bash
agent-mail-helper whoami                    # Show current identity
agent-mail-helper inbox                     # Check inbox
agent-mail-helper send <agent> <message>    # Send message
agent-mail-helper broadcast <message>       # Broadcast to all
agent-mail-helper register "<role>"         # Register with role
```

Commands:
- `register` - Register agent with role
- `whoami` - Show current agent identity
- `list` - List all registered agents
- `send` - Send direct message
- `inbox` - Check inbox
- `unread` - Show unread count
- `mark-read` - Mark message as read
- `mark-all-read` - Mark all messages read
- `broadcast` - Send to all agents
- `test-message` - Send test message

## Monitoring Tools

### monitor-agent-mail
Real-time agent mail notification display in terminal.

```bash
monitor-agent-mail
```

Features:
- Displays incoming messages in real-time
- Auto-resolves pane identity changes
- Handles queue injection for commands
- TTL-based message expiry

### mail-monitor-ctl
Daemon control for mail monitor.

```bash
mail-monitor-ctl start     # Start monitor
mail-monitor-ctl stop      # Stop monitor
mail-monitor-ctl status    # Check status
mail-monitor-ctl restart   # Restart monitor
```

### terminal-inject
Command queue injection system.

```bash
terminal-inject "command to run"
```

Features:
- JSON-based queue with timestamps
- Idempotency via MD5 hashing
- Millisecond precision timestamps
- Consumed by mail monitor

## Task Management

### br-start-work
Interactive workflow to start new bead or claim existing.

```bash
br-start-work ["bead title"]
```

Features:
- Creates new bead with work brief
- Claims next recommended bead from queue
- Sets active bead for current session
- Integrates with bv recommendations

### bv-claim
Quick claim of next recommended bead.

```bash
bv-claim
```

Wrapper around `bv --robot-next`.

### next-bead
Get next recommended bead ID.

```bash
next-bead
```

Returns bead ID from `bv --robot-next`.

## Multi-Agent Tools

### broadcast-to-swarm
Send message to all registered agents.

```bash
broadcast-to-swarm "message to all agents"
```

Uses agent-mail-helper broadcast internally.

## Utilities

### hook-bypass
Manage git hook bypass mode for testing.

```bash
hook-bypass on      # Enable bypass
hook-bypass off     # Disable bypass
hook-bypass status  # Check status
```

## Architecture

### Directory Structure

```
agent_workflow/
├── agent-runner              # Core workflow automation
├── visual-session-manager    # Session management UI
├── agent-mail-helper         # MCP client wrapper
├── monitor-agent-mail        # Real-time notifications
├── mail-monitor-ctl          # Monitor daemon control
├── terminal-inject           # Command queue system
├── br-start-work             # Task workflow starter
├── bv-claim                  # Quick task claim
├── next-bead                 # Next task retriever
├── broadcast-to-swarm        # Multi-agent broadcast
├── hook-bypass               # Hook management
├── lib/                      # Shared libraries
│   ├── pane-init.sh          # Pane initialization
│   └── project-config.sh     # Project configuration
└── install.sh                # Installation script
```

### Dependencies

**Required:**
- `tmux` - Terminal multiplexer
- `fzf` - Fuzzy finder (for visual-session-manager)
- `jq` - JSON processor
- `python3` - For some helper scripts

**Optional (for full functionality):**
- `br` (beads_rust) - Task management
- `bv` (beads_viewer) - Task visualization
- MCP Agent Mail server - Multi-agent coordination

### Integration Points

1. **MCP Agent Mail** - agent-mail-helper, monitor-agent-mail
2. **Beads Task System** - br-start-work, bv-claim, next-bead
3. **tmux Sessions** - visual-session-manager, agent-runner
4. **Git Hooks** - hook-bypass

## Workflows

### Autonomous Agent Workflow

```bash
# 1. Start MCP Agent Mail server
cd ~/Projects/AgentCore/mcp_agent_mail
python -m mcp_agent_mail serve-http &

# 2. Launch session manager
visual-session-manager

# 3. In new session, run agent
agent-runner bd-xxxx
```

### Multi-Agent Coordination

```bash
# Launch 3 agents in tmux panes
tmux new-session -s swarm \; \
  split-window -h \; \
  split-window -v \; \
  select-pane -t 0 \; send-keys "agent-runner bd-001" C-m \; \
  select-pane -t 1 \; send-keys "agent-runner bd-002" C-m \; \
  select-pane -t 2 \; send-keys "agent-runner bd-003" C-m

# Broadcast to all agents
broadcast-to-swarm "Team: let's coordinate on this task"
```

### Task Management Workflow

```bash
# Start new work
br-start-work "Implement feature X"

# Or claim next recommended
bv-claim

# Check what's next
next-bead
```

## Configuration

### Environment Variables

- `MAIL_PROJECT_KEY` - Project identifier for agent mail (default: current directory)
- `PROJECT_ROOT` - Project root directory (default: current directory)
- `CLAUDE_PROJECT_DIR` - Claude Code project directory
- `AGENT_RUNNER_BEAD` - Pre-assigned bead for agent-runner

### MCP Agent Mail

Agent mail features require MCP Agent Mail server running:

```bash
cd ~/Projects/AgentCore/mcp_agent_mail
source venv/bin/activate
python -m mcp_agent_mail serve-http
```

Default: http://localhost:8765

## Troubleshooting

### Agent mail not working
- Verify MCP server is running: `curl http://localhost:8765/health`
- Check registration: `agent-mail-helper whoami`
- Re-register: `agent-mail-helper register "Your Role"`

### Monitor not displaying messages
- Check monitor is running: `mail-monitor-ctl status`
- Restart: `mail-monitor-ctl restart`
- Verify pane targeting in tmux

### Scripts can't find lib files
- Reinstall: `./install.sh`
- Verify lib location: `ls ~/.local/lib/agent_workflow/`

## Examples

See AgentCore documentation for complete workflow examples.

## Migration Notes

These tools were migrated from agent-flywheel-integration to provide system-wide agent workflow capabilities without per-project duplication.

Original location: `~/Projects/agent-flywheel-integration/scripts/`
