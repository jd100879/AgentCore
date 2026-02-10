# Flywheel Tools

> Shell script infrastructure for autonomous agent workflows, task management, and multi-agent coordination

**Flywheel Tools** provides the essential shell script infrastructure that powers the [Agent Flywheel](http://agent-flywheel.com/tldr) pattern: autonomous agents that continuously pick up tasks (beads), work on them, and move to the next task without human intervention.

## What is This?

Flywheel Tools is a collection of ~68 shell scripts that enable:

- **Autonomous Agent Operation**: Agents run continuously, picking up and completing tasks
- **Task Management (Beads)**: Integration with `br` (beads_rust) for git-backed task tracking
- **Multi-Agent Coordination**: Fleet management, swarm orchestration, and agent communication
- **Workflow Automation**: Hooks that enforce workflow rules and track activity
- **Terminal Integration**: tmux-based agent coordination and command injection
- **Model Adapters**: Support for Grok (xAI) and DeepSeek alongside Claude

## Quick Start

### Prerequisites

- **beads_rust** (`br` command): Git-backed task tracker
- **MCP Agent Mail**: Multi-agent communication server
- **tmux**: Terminal multiplexer for agent coordination
- **bash** 4.0+: Shell environment

### Installation

```bash
# 1. From AgentCore root
cd AgentCore/flywheel_tools

# 2. Run the installer (creates symlinks to your project)
./install.sh /path/to/your/project

# 3. Configure project
cd /path/to/your/project
export PROJECT_ROOT="$(pwd)"
export MAIL_PROJECT_KEY="$PROJECT_ROOT"

# 4. Initialize beads
br init

# 5. Verify installation
./scripts/doctor.sh
```

See [docs/installation.md](docs/installation.md) for detailed setup instructions.

## Core Workflow

### 1. Start an Autonomous Agent

```bash
# Launch an agent that continuously works through beads
./scripts/agent-runner.sh

# Start with a specific bead
./scripts/agent-runner.sh --bead bd-abc123

# Preview without launching
./scripts/agent-runner.sh --dry-run
```

**How it works:**
1. Agent detects its identity via Agent Mail
2. Claims next recommended bead from queue
3. Launches Claude with cycling instructions
4. Works bead, commits with `[BEAD-ID]` prefix
5. Closes bead, claims next, repeats

### 2. Create and Manage Tasks

```bash
# Create a bead with work brief
./scripts/br-create.sh "Fix login timeout" --type bug --parent bd-xxx

# View open beads
./scripts/bv-open.sh

# Claim a bead
./scripts/bv-claim.sh bd-abc123

# Close a bead
br close bd-abc123
```

### 3. Wake Idle Agents

```bash
# Touch wake trigger for idle agents
./scripts/wake-agents.sh

# Wake and broadcast notification
./scripts/wake-agents.sh --notify "New high-priority work" --bead bd-urgent
```

## Directory Structure

```
flywheel_tools/
├── scripts/
│   ├── core/         # Agent lifecycle (agent-runner, wake-agents, next-bead)
│   ├── hooks/        # Workflow automation (pre-edit, post-bash, session hooks)
│   ├── beads/        # Task management (br-create, bv-claim, monitoring)
│   ├── terminal/     # Terminal integration (arrange-panes, terminal-inject)
│   ├── fleet/        # Multi-agent coordination (fleet-status, swarm-metrics)
│   ├── monitoring/   # Metrics and tracking (reservation-metrics, performance)
│   ├── dev/          # Development tools (doctor, hook-bypass, self-review)
│   ├── adapters/     # Model adapters (grok-claude-wrapper, deepseek-adapter)
│   └── lib/          # Shared utilities (project-config, pane-init)
├── config/           # Configuration templates
├── tests/            # Unit and integration tests
├── docs/             # Documentation
└── install.sh        # Project installation script
```

## Components

### Core Infrastructure

**Scripts**: agent-runner.sh, wake-agents.sh, next-bead.sh, lib/project-config.sh

The foundation of autonomous agent operation:

- **agent-runner.sh**: Main execution loop that keeps agents working continuously
- **wake-agents.sh**: Notifies idle agents when new work is available
- **next-bead.sh**: Claims next task and clears context between beads
- **lib/project-config.sh**: Shared configuration and path management

### Workflow Hooks

**Scripts**: 8 hooks for session, edit, and bash tracking

Enforce workflow rules and automate common tasks:

- **session-start-hook.sh** / **session-stop-hook.sh**: Session lifecycle
- **pre-edit-check-hook.sh**: Validates bead exists before edits
- **pre-bash-bead-check-hook.sh**: Ensures bead context for commands
- **post-bash-bead-track-hook.sh**: Logs bash commands to bead history
- **post-bead-close-hook.sh**: Automates cleanup when beads close
- **pre-task-block-hook.sh**: Prevents conflicting task assignments

### Beads Integration

**Scripts**: br-create.sh, br-start-work.sh, bv-claim.sh, bead-quality-scorer.sh, +7 more

Task management integration:

- **br-create.sh**: Creates beads with automatic work brief enrichment
- **br-start-work.sh**: Starts work on a bead with context setup
- **bv-claim.sh**: Claims recommended beads for work
- **log-bead-activity.sh**: Activity logging for metrics
- **bead-stale-monitor.sh**: Detects stale/abandoned beads
- **bead-quality-scorer.sh**: Scores bead quality for triage

### Terminal & Fleet Management

**Scripts**: terminal-inject.sh, fleet-status.sh, assign-tasks.sh, +8 more

Multi-agent coordination in tmux:

- **terminal-inject.sh**: Queue commands for terminal injection
- **arrange-panes.sh**: Organize tmux panes for agents
- **fleet-core.sh** / **fleet-status.sh**: Fleet management and metrics
- **swarm-status.sh** / **swarm-metrics.sh**: Swarm coordination
- **assign-tasks.sh**: Distribute tasks across agents

### Monitoring & Metrics

**Scripts**: performance-tracker.sh, reservation-metrics.sh, metrics-summary.sh, +3 more

System observability:

- **performance-tracker.sh**: Track agent performance over time
- **reservation-metrics.sh**: File reservation usage
- **metrics-summary.sh**: Aggregate metrics across agents
- **expiry-notify-monitor.sh**: Alert on expiring reservations

### Development Tools

**Scripts**: doctor.sh, hook-bypass.sh, self-review.sh, +13 more

Development and debugging:

- **doctor.sh**: System health check and diagnostics
- **hook-bypass.sh**: Temporarily disable hooks for testing
- **self-review.sh**: Automated code review
- **validate-agent-session.sh**: Session state validation
- **generate-task-graph.sh**: Visualize task dependencies
- **visual-session-manager.sh**: Interactive session management UI

### Model Adapters

**Scripts**: grok-claude-wrapper.sh, deepseek-claude-wrapper.sh, +2 more

Alternative model support:

- **grok-claude-wrapper.sh**: Drop-in Grok (xAI) replacement for Claude
- **deepseek-claude-wrapper.sh**: DeepSeek model adapter
- **setup-codex-oauth.sh**: OAuth configuration for Codex

## Configuration

Flywheel Tools expects these environment variables:

```bash
# Required
export PROJECT_ROOT="/path/to/your/project"
export MAIL_PROJECT_KEY="$PROJECT_ROOT"

# Optional
export AGENT_RUNNER_IDLE_SLEEP=60        # Seconds to sleep when no beads (default: 60)
export AGENT_RUNNER_MAX_IDLE=10          # Max idle checks before exit (default: 10)
export AGENT_RUNNER_MAX_RESTARTS=5       # Max crash restarts (default: 5)
```

## Integration with AgentCore

Flywheel Tools is part of the AgentCore ecosystem:

- **beads_rust** (`br`): Task tracking backend
- **beads_viewer** (`bv`): Task visualization and triage
- **mcp_agent_mail**: Multi-agent communication
- **flywheel_tools**: Shell script automation (this component)

Together, these enable the full Agent Flywheel pattern.

## Migration Status

**Status**: Active migration from agent-flywheel-integration

This component is being migrated in phases:

- **Phase 1** (In Progress): Core infrastructure and hooks
- **Phase 2** (Planned): Beads integration scripts
- **Phase 3** (Planned): Terminal and fleet management
- **Phase 4** (Planned): Monitoring and metrics
- **Phase 5** (Planned): Development tools and adapters

Current migration: ~68 scripts across 6 phases.

See the [migration plan](docs/migration-status.md) for details.

## Documentation

- [Installation Guide](docs/installation.md) - Detailed setup instructions
- [Quick Start Guide](docs/quick-start.md) - Get up and running fast
- [Script Reference](docs/scripts-reference.md) - All scripts documented
- [Integration Guide](docs/integration.md) - Using with your project

## Requirements

- **bash** 4.0+
- **tmux** 3.0+
- **git** 2.20+
- **jq** 1.6+
- **python** 3.8+ (for some utilities)
- **beads_rust** (`br` command)
- **MCP Agent Mail** server

## License

MIT

## Credits

Part of Jeffrey Emanuel's [Agent Flywheel](http://agent-flywheel.com/tldr) system.
