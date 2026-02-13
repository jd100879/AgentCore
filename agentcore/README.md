# AgentCore Coordination Infrastructure

This directory contains the **coordination plane** for the AgentCore multi-agent system. It is the central infrastructure that enables agent collaboration, task management, and inter-agent communication.

## Scope

The `agentcore/` directory is strictly for **coordination infrastructure only**:

- **Agent coordination**: Registry, panes, sessions, profiles
- **State management**: Beads (task tracking), notifications, audit logs
- **Runtime artifacts**: PIDs, logs, temporary files
- **Configuration**: Flywheel, agent settings, NTM config
- **Communication**: Mail pointers (to shared external repo)
- **Tools**: Coordination scripts (mail, registry, monitoring)
- **Schemas**: Data contracts for coordination protocols
- **Verification**: Integrity checks and smoke tests

**NOT in scope** (these remain as peer components at project root):
- `beads_rust/` - Bead management implementation
- `flywheel_tools/` - Tools for spoke projects
- `mcp_agent_mail/` - Mail server implementation
- Other project-specific tools and documentation

## Architecture: Hub-and-Spoke

**AgentCore = The Hub**
- Where coordination tools are developed, tested, and proven
- Contains this `agentcore/` coordination directory
- Maintains the authoritative coordination infrastructure

**Other Projects = Spokes**
- Consumer projects that use AgentCore's coordination tools
- Install via `flywheel_tools/install.sh`
- Connect to shared mail infrastructure
- Share workspace-global communication channels

## Hard Invariants

These rules MUST be maintained to prevent drift and ensure system integrity:

### 1. No Hidden Directories Inside agentcore/
All subdirectories within `agentcore/` are explicitly listed and documented. No `.dotdirs` or hidden structures inside this tree. Hidden coordination state lives at project root (e.g., `.beads/`, `.panes/`) and is **referenced via symlinks** from agentcore.

### 2. Peer Components Stay at Top-Level
Components like `beads_rust/`, `flywheel_tools/`, and `mcp_agent_mail/` remain at the project root. They are peers to `agentcore/`, not subdirectories. The `agentcore/` directory is specifically for the coordination plane, not for absorbing the entire project.

### 3. Mail is Shared and External
The agent mail system is **workspace-global infrastructure** by design:
- **Shared repository**: `$HOME/.mcp_agent_mail_local_repo/`
- **Shared MCP server**: Runs on port 8765
- **Cross-project communication**: Agents from different projects can communicate
- **agentcore reference**: Points to external mail via `mail/repo-location.txt`

The mail directory is NOT moved into agentcore; it remains an external shared resource.

### 4. Coordination Tools Only
Scripts in `agentcore/tools/` are **coordination-specific**:
- Agent registry and mail helpers
- State monitoring and verification
- Shared path utilities (lib/paths.sh)

General project scripts remain in the top-level `scripts/` directory.

## Mail Infrastructure (Shared)

The agent mail system operates outside the agentcore directory structure:

```
$HOME/.mcp_agent_mail_local_repo/          # Shared across ALL projects
├── mail_store/                            # Message storage
├── metadata.json                          # Workspace metadata
└── ...

AgentCore/agentcore/mail/
├── repo-location.txt                      # Points to shared repo
└── repo/ → $HOME/.mcp_agent_mail_local_repo/  # Optional symlink
```

**MCP Mail Server**:
- Runs as a shared service on port 8765
- Started via `mcp_agent_mail/server.py`
- Accessible by all agents workspace-wide
- Configuration in `mcp_agent_mail/config/mail.yaml`

## Migration Phases

This directory is being established through a careful **3-phase migration**:

### Phase 1: Additive Setup (CURRENT)
**Status**: In Progress
**Posture**: Additive-only, non-disruptive

- Create `agentcore/` directory skeleton
- Create **outward symlinks** (agentcore points to existing locations)
  - `state/beads/` → `../../.beads/`
  - `runtime/logs/` → `../../tmp/`
  - `tools/agent-mail-helper.sh` → `../../scripts/agent-mail-helper.sh`
- Add verification scripts in `verify/`
- Document invariants (this README)
- **No files moved**, **no paths broken**

**Rollback**: Delete `agentcore/` directory (nothing else affected)

### Phase 2: Make Authoritative (FUTURE)
**Status**: Not started
**Trigger**: After Phase 1 proven stable for multiple work sessions

- Move coordination files **into agentcore**
- Flip symlinks **inward** (old paths point to agentcore)
- Scripts prefer `AGENTCORE_ROOT` paths
- Rollback script ready before starting
- **Do only after Phase 1 stability confirmed**

### Phase 3: Complete Cleanup (FUTURE)
**Status**: Not started
**Trigger**: Weeks after Phase 2 proven stable

- Remove legacy symlinks
- Add canonical paths library (`tools/lib/paths.sh`)
- Enforce drift guards (CI checks)
- Clean-room smoke tests
- **Do only after Phase 2 stability confirmed**

## Directory Structure (Phase 1)

```
agentcore/
├── README.md                           # This file
├── config/                             # Configuration files
│   ├── flywheel/ → ../../.flywheel/   # Symlink to flywheel config
│   ├── agents/ → ../../.agents/       # Symlink to agent config
│   └── ntm/ → ../../.ntm/             # Symlink to NTM config
├── state/                              # State and tracking
│   ├── beads/ → ../../.beads/         # Symlink to bead state
│   ├── notifications/ → ../../.notifications/  # Symlink to notifications
│   └── audit/ → ../../.audit/         # Symlink to audit logs
├── runtime/                            # Runtime artifacts
│   ├── pids/ → ../../.pids/           # Symlink to process IDs
│   ├── panes/ → ../../.panes/         # Symlink to tmux panes
│   ├── sessions/ → ../../.sessions/   # Symlink to session info
│   ├── logs/ → ../../tmp/             # Symlink to log files
│   └── tmp/ → ../../tmp/              # Symlink to temp files
├── coordination/                       # Coordination state
│   ├── profiles/ → ../../.profiles/   # Symlink to agent profiles
│   ├── workflows/ → ../../.workflows/ # Symlink to workflow state
│   └── active/ → ../../.active/       # Symlink to active sessions
├── mail/                               # Mail system pointer
│   ├── repo-location.txt              # Path to shared mail repo
│   └── repo/ → $HOME/.mcp_agent_mail_local_repo/  # Optional symlink
├── tools/                              # Coordination scripts
│   ├── agent-mail-helper.sh → ../../scripts/agent-mail-helper.sh
│   ├── agent-registry.sh → ../../scripts/agent-registry.sh
│   └── lib/                            # Shared utilities (future)
├── schemas/                            # Data contracts
│   └── (TBD)                           # Protocol schemas
└── verify/                             # Verification scripts
    ├── check-structure.sh              # Verify directory structure
    ├── check-symlinks.sh               # Verify symlink integrity
    └── smoke-tests.sh                  # End-to-end tests
```

## Verification

After each phase, run verification to ensure integrity:

```bash
# Check directory structure
./agentcore/verify/check-structure.sh

# Verify all symlinks resolve correctly
./agentcore/verify/check-symlinks.sh

# Run smoke tests
./agentcore/verify/smoke-tests.sh
```

## Design Principles

1. **Explicit over implicit**: All structure is documented and verified
2. **Reversible migrations**: Each phase has a clear rollback path
3. **Stability first**: Prove each phase stable before proceeding
4. **Defensive verification**: Check assumptions, validate state
5. **Shared infrastructure**: Mail is workspace-global by design
6. **Clean boundaries**: Coordination vs implementation vs general tooling

## When to Escalate

Stop and escalate if:
- A symlink would create a cycle
- Verification scripts fail after changes
- Behavior differs from documented invariants
- Unsure whether a file belongs in coordination or elsewhere
- Changes would affect running agents or active sessions

## Questions?

See also:
- `../AGENTS.md` - Agent workflow and bead tracking
- `../AGENT_MAIL.md` - Inter-agent communication
- `../flywheel_tools/README.md` - Spoke installation
- `../mcp_agent_mail/README.md` - Mail server implementation
