# Flywheel Tools Quick Start Guide

Get up and running with autonomous agents in 10 minutes.

## Overview

This guide walks you through:
1. Setting up your first agent
2. Creating and working a task (bead)
3. Launching an autonomous agent
4. Coordinating multiple agents

## Prerequisites

Ensure you have Flywheel Tools installed. If not, see [Installation Guide](installation.md).

## Step 1: Initialize Your Project

```bash
# Set project root
export PROJECT_ROOT="$(pwd)"
export MAIL_PROJECT_KEY="$PROJECT_ROOT"

# Initialize beads
br init

# Verify setup
./scripts/doctor.sh
```

Expected output: All checks passing ✓

## Step 2: Register Agent Identity

Each agent needs a unique identity for coordination:

```bash
# Register yourself
./scripts/agent-mail-helper.sh register "Development agent"

# Check your identity
./scripts/agent-mail-helper.sh whoami
# Output: TurquoiseGrove (or another random name)
```

Your agent name (like `TurquoiseGrove`) is randomly assigned and persists across sessions.

## Step 3: Create Your First Bead

Beads are tasks tracked in git. Create one:

```bash
# Simple creation
./scripts/br-create.sh "Add user authentication"

# With details
./scripts/br-create.sh "Fix login timeout" \
  --type bug \
  --priority 1 \
  --description "Users report 30s timeout on login"

# With parent bead (sub-task)
./scripts/br-create.sh "Write auth tests" \
  --parent bd-abc123 \
  --type qa
```

The script auto-infers the work brief type from keywords and enriches the description with constraints.

## Step 4: View and Claim Beads

```bash
# View all open beads
./scripts/bv-open.sh

# View ready-to-work beads (no blockers)
br ready

# Claim a specific bead
./scripts/bv-claim.sh bd-abc123

# Or let Robot Mode recommend one
./scripts/br-robot-next --auto-claim
```

## Step 5: Work on a Bead

Once claimed, start working:

```bash
# Method 1: Direct work
br start bd-abc123
# ... make changes ...
git add .
git commit -m "[bd-abc123] Implement login timeout fix"
br close bd-abc123

# Method 2: Using br-start-work wrapper
./scripts/br-start-work.sh "Fix login timeout"
# Auto-creates bead, claims it, sets up context
```

**Important**: All commits must include `[bd-xxx]` prefix. Hooks enforce this.

## Step 6: Launch an Autonomous Agent

For continuous operation without human intervention:

```bash
# Start agent runner (picks up beads automatically)
./scripts/agent-runner.sh

# Or with specific bead
./scripts/agent-runner.sh --bead bd-abc123

# Preview without launching
./scripts/agent-runner.sh --dry-run
```

**What happens:**
1. Agent detects identity
2. Claims next recommended bead
3. Launches Claude with cycling instructions
4. Works bead → commits → closes → claims next → repeats
5. On crash: restarts up to 5 times
6. On idle: sleeps 60s, checks for new beads

## Step 7: Multi-Agent Coordination

### Send Messages Between Agents

```bash
# Send a message
./scripts/agent-mail-helper.sh send 'OtherAgent' \
  '[bd-abc123] API endpoint ready' \
  'The /auth endpoint is deployed and ready for frontend integration'

# Check inbox
./scripts/agent-mail-helper.sh inbox

# List all agents
./scripts/agent-mail-helper.sh list
```

### Wake Idle Agents

When new high-priority work arrives:

```bash
# Wake all idle agents
./scripts/wake-agents.sh

# Wake and broadcast
./scripts/wake-agents.sh \
  --notify "Critical bug fix needed" \
  --bead bd-urgent
```

### Monitor Mail in tmux

Enable automatic mail notifications in your tmux pane:

```bash
# Start monitor (binds to current pane)
./scripts/mail-monitor-ctl.sh start

# Check status
./scripts/mail-monitor-ctl.sh status

# Stop monitor
./scripts/mail-monitor-ctl.sh stop
```

New messages appear as tmux notifications.

## Step 8: View Fleet Status

Monitor all active agents:

```bash
# Full dashboard
./scripts/fleet-status.sh

# Compact summary
./scripts/fleet-status.sh --compact

# Watch mode (updates every 2s)
./scripts/fleet-status.sh --watch

# JSON output
./scripts/fleet-status.sh --json
```

Example output:
```
Fleet Status
============
Active: 3 agents
Idle:   1 agent

TurquoiseGrove  [ACTIVE]  bd-abc123  Backend
SapphireGate    [ACTIVE]  bd-def456  Frontend
OrangePond      [ACTIVE]  bd-ghi789  DevOps
QuietRiver      [IDLE]    -          -
```

## Common Workflows

### Creating Sub-Tasks

Break down large beads:

```bash
# Parent bead
./scripts/br-create.sh "Implement user auth system" --type backend
# Output: bd-parent

# Child beads
./scripts/br-create.sh "Add JWT generation" --parent bd-parent
./scripts/br-create.sh "Add password hashing" --parent bd-parent
./scripts/br-create.sh "Add session management" --parent bd-parent

# View hierarchy
br show bd-parent
```

### Handling Errors

If a bead fails or needs help:

```bash
# Add notes to bead
br update bd-abc123 --description "Additional context: API key missing"

# Create blocking bead
./scripts/br-create.sh "Fix API key configuration" --type devops
br block bd-abc123 --by bd-blocker

# Alert another agent
./scripts/agent-mail-helper.sh send 'DevOpsAgent' \
  'Need API key config' \
  'Please configure production API keys for bd-abc123'
```

### Coordinating Work

Avoid conflicts with file reservations:

```bash
# Check what's reserved
./scripts/reserve-files.sh list-all

# Reserve files (via agent mail tool)
# This is typically done automatically by MCP Agent Mail
# See MCP Agent Mail documentation for reservation API
```

### Hook Bypass (Testing Only)

During development/testing, temporarily disable hooks:

```bash
# Enable bypass
./scripts/hook-bypass.sh on

# ... make test changes without bead ...

# Disable bypass (IMPORTANT!)
./scripts/hook-bypass.sh off

# Check status
./scripts/hook-bypass.sh status
```

**Warning**: Never commit with hooks bypassed. Always re-enable before committing.

## Next Steps

### Learn More

- [Hooks Reference](hooks.md) - All workflow hooks explained
- [Script Reference](scripts-reference.md) - Complete script documentation
- [Integration Guide](integration.md) - Integrate with your workflow

### Advanced Topics

- **Swarm Orchestration**: Coordinate 5+ agents on complex projects
- **Fleet Metrics**: Track agent productivity and bottlenecks
- **Custom Work Briefs**: Define domain-specific constraints
- **Model Adapters**: Use Grok or DeepSeek alongside Claude

### Troubleshooting

Having issues? See [Troubleshooting Guide](troubleshooting.md) or run:

```bash
./scripts/doctor.sh
```

## Example: Complete Session

Here's a complete session from start to finish:

```bash
# 1. Setup
export PROJECT_ROOT="$(pwd)"
br init
./scripts/agent-mail-helper.sh register "Dev agent"

# 2. Create work
./scripts/br-create.sh "Add login API endpoint" --type backend
# Output: bd-abc123

# 3. Claim and work
./scripts/bv-claim.sh bd-abc123
# ... implement the feature ...
git add src/api/auth.py
git commit -m "[bd-abc123] Add login endpoint with JWT"

# 4. Close bead
br close bd-abc123

# 5. Start autonomous operation
./scripts/agent-runner.sh
# Agent now continuously picks up and works beads
```

## Tips for Success

1. **Always use bead IDs in commits**: `[bd-xxx]` prefix is mandatory
2. **Check inbox regularly**: `./scripts/agent-mail-helper.sh inbox`
3. **Break down large tasks**: Use parent-child bead hierarchies
4. **Monitor fleet status**: Know what other agents are doing
5. **Use wake-agents**: Alert team when urgent work arrives
6. **Verify with doctor.sh**: Run health checks if anything feels off

## Getting Help

- Run `./scripts/doctor.sh` for diagnostics
- Check logs in `.beads/*.log`
- Review agent activity: `./scripts/log-bead-activity.sh --summary`
- Ask in Agent Flywheel community

You're now ready to run autonomous agents with Flywheel Tools!
