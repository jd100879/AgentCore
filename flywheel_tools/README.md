# Flywheel Tools

A comprehensive toolkit for autonomous agent workflows, task management, and multi-agent coordination.

## Overview

Flywheel Tools provides the essential infrastructure for running autonomous agents with task tracking (beads), multi-agent coordination, terminal integration, and comprehensive monitoring.

## Directory Structure

```
flywheel_tools/
├── scripts/
│   ├── core/         # Core agent infrastructure (agent-runner, wake-agents, next-bead)
│   ├── hooks/        # Workflow automation hooks (session, edit, bash tracking)
│   ├── beads/        # Beads task management (br-*, bv-*, monitoring)
│   ├── terminal/     # Terminal integration (arrange-panes, terminal-inject)
│   ├── fleet/        # Fleet management and coordination
│   ├── monitoring/   # System monitoring and metrics
│   ├── dev/          # Development tools (doctor, hook-bypass, self-review)
│   ├── adapters/     # Model adapters (grok, deepseek)
│   └── lib/          # Shared libraries and utilities
├── tests/            # Unit tests for all components
├── docs/             # Additional documentation
└── install.sh        # Installation script for projects
```

## Installation

See [docs/installation.md](docs/installation.md) for installation instructions.

## Migration Status

This component is being actively migrated from agent-flywheel-integration. See [docs/migration.md](docs/migration.md) for details.

## Components

### Core Infrastructure (Phase 1)
- **agent-runner.sh**: Main agent execution loop
- **wake-agents.sh**: Agent startup orchestration
- **next-bead.sh**: Autonomous work assignment
- **Hooks**: Session, edit validation, bash tracking, workflow automation

### Beads Integration (Phase 2)
- **br-* scripts**: Create and manage beads (tasks)
- **bv-* scripts**: View and claim beads
- **Monitoring**: Activity logging, stale detection, quality scoring

### Terminal & Fleet (Phase 3)
- **Terminal integration**: Pane management, command injection
- **Fleet management**: Multi-agent coordination and metrics

### Monitoring (Phase 4)
- **Reservation monitoring**: File reservation tracking
- **Metrics aggregation**: Performance and usage metrics

### Development Tools (Phase 5)
- **Dev tools**: System health checks, hook bypass, session validation
- **Task analysis**: Task graphs, lifecycle tracking
- **Model adapters**: Grok and DeepSeek integration

## Usage

See component-specific documentation in the `docs/` directory.

## License

MIT
