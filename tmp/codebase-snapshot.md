# AgentCore Current Codebase Structure

## Top-Level Directory Layout

```
/Users/james/Projects/AgentCore/
├── Component Directories (major subsystems)
│   ├── mcp_agent_mail/          # Agent mail MCP server
│   ├── beads_rust/              # Task tracking backend (br CLI)
│   ├── beads_viewer/            # Task visualization TUI (bv CLI)
│   ├── flywheel_tools/          # Shell script infrastructure
│   ├── ntm/                     # NTM system
│   ├── ultimate_bug_scanner/    # Static analysis
│   ├── coding_agent_session_search/  # Semantic search
│   ├── wezterm_automata/        # Terminal automation
│   ├── markdown_web_browser/    # Web scraping
│   ├── cass_memory_system/      # Memory system
│   ├── repo_updater/            # Repo update tools
│   └── slb/                     # SLB system
│
├── Hidden Agent Coordination Directories
│   ├── .agent-coordination/     # Currently has only placeholder
│   ├── .agent-profiles/         # Contains types.yaml
│   ├── .agent-workflows/        # Currently empty
│   ├── .active-agents/          # Currently empty
│   ├── .beads/                  # Beads git backend (issues.jsonl, git commits)
│   ├── .flywheel/               # Flywheel config (bridge/, chatgpt.json, orchestrator docs)
│   ├── .disk-notifications/     # Notifications
│   ├── .session-state/          # Session state
│   └── .ntm/                    # NTM config
│
├── Scripts (scattered)
│   ├── scripts/
│   │   ├── agent-mail-helper.sh
│   │   ├── agent-control.sh
│   │   ├── agent-registry.sh
│   │   ├── auto-register-agent.sh
│   │   ├── plan-to-agents.sh
│   │   ├── monitor-agent-mail-to-terminal.sh
│   │   ├── mail-monitor-ctl.sh
│   │   ├── start-multi-agent-session.sh
│   │   ├── chatgpt/
│   │   │   ├── batch-plan.mjs
│   │   │   └── post-and-extract.mjs
│   │   └── lib/
│   │
│   └── Symlinks to flywheel_tools:
│       ├── agent-runner.sh -> ../flywheel_tools/scripts/core/agent-runner.sh
│       └── validate-agent-session.sh -> ../flywheel_tools/scripts/dev/validate-agent-session.sh
│
├── State & Temporary
│   ├── state/logs/              # Log files
│   ├── tmp/                     # Temp files
│   ├── pids/                    # Process IDs
│   ├── panes/                   # Tmux pane info
│   └── workflows/               # Empty
│
├── Testing & Review
│   ├── test-results/
│   ├── review-for-delete/
│   └── archive/
│
├── Schemas
│   └── schemas/flywheel/
│
├── Tools
│   └── tools/agent_workflow/
│
└── Nearly Empty Directory (confusing!)
    └── AgentCore/               # Only contains .gitattributes!
```

## Current Agent Mail Architecture

### How Agent Mail Works Today

**Backend**: MCP Agent Mail server (Python FastAPI)
- **Location**: `mcp_agent_mail/` directory (separate component)
- **Server**: Runs on port 8765 (docker-compose)
- **Storage**: Git-backed messages in `$HOME/.mcp_agent_mail_local_repo/`
  ```
  $HOME/.mcp_agent_mail_local_repo/
  ├── inbox/
  │   ├── AgentA/
  │   └── AgentB/
  └── sent/
  ```

**Agent Interface**: Scripts in `scripts/`
- `agent-mail-helper.sh` - Main interface (send, inbox, whoami, list)
- `monitor-agent-mail-to-terminal.sh` - Notification monitor
- `mail-monitor-ctl.sh` - Monitor control
- `agent-registry.sh` - Agent identity management
- `auto-register-agent.sh` - Auto-registration on session start

**Data Flow**:
```
Agent → agent-mail-helper.sh → HTTP POST :8765
                                    ↓
MCP Server → git commit → $HOME/.mcp_agent_mail_local_repo/inbox/$RECIPIENT/
                                    ↓
Recipient agent-mail-helper.sh inbox → git pull → read messages
```

### Current Mail System Issues (from user)

- Deterministic routing needed
- Reliable dispatch/processing
- Strong idempotency/locking
- Clear observability/recovery
- Folder semantics unclear (inbox → processing → done/failed flow)

## Key Configuration Files

- **Beads**: `.beads/issues.jsonl` (current state), `.beads/beads.db` (sqlite)
- **Agent tracking**: `.beads/agent-activity.jsonl`, `.beads/mail-read.jsonl`
- **Flywheel**: `.flywheel/chatgpt.json`, `.flywheel/orchestrator-instructions.md`
- **Agent profiles**: `.agent-profiles/types.yaml`
- **NTM**: `.beads/ntm-config.yaml`

## Documentation Files

- `ARCHITECTURE.md` - System architecture overview
- `AGENTS.md` - Agent workflow guide (11KB)
- `AGENT_MAIL.md` - Mail system commands (2KB)
- `CLAUDE.md` - Project instructions
- `GETTING_STARTED.md` - Getting started guide
- `PRACTICAL_USAGE.md` - Usage patterns
- `STATUS.md` - Current status
- `README.md` - Main readme

## What Exists vs What's Needed

### Currently Scattered Across:
- Hidden dot directories (`.agent-*`, `.beads/`, `.flywheel/`)
- Component directories (`mcp_agent_mail/`, `flywheel_tools/`)
- Top-level `scripts/` directory
- External git repo (`$HOME/.mcp_agent_mail_local_repo/`)

### User's Goal:
Create a clean, deterministic `/agentcore` directory structure that:
1. Centralizes agent coordination infrastructure
2. Makes mail system deterministic and observable
3. Defines clear folder semantics (inbox → processing → done/failed)
4. Supports idempotency, locking, routing, and recovery

### Note:
There's an existing `AgentCore/` directory (capital A) but it only contains `.gitattributes` - appears to be legacy/unused.
