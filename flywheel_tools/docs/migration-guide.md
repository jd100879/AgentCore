# Flywheel Tools Migration Guide

This guide helps existing projects adopt Flywheel Tools for autonomous agent workflows.

## Overview

Flywheel Tools provides shell script infrastructure for:
- Autonomous agent operation
- Task management (beads integration)
- Multi-agent coordination
- Workflow automation via hooks

This guide covers migrating from manual agent workflows to the Flywheel Tools automation suite.

## Who Should Use This Guide

This guide is for projects that:
- Use `br` (beads_rust) for task management
- Run Claude Code or other LLM agents
- Want to automate agent workflows
- Need multi-agent coordination
- Have existing custom agent scripts to migrate

## Migration Strategy

### Phase-Based Approach (Recommended)

Migrate incrementally to minimize risk and validate each phase:

**Phase 1: Core Infrastructure** (Start here)
- Scripts: `agent-runner.sh`, `wake-agents.sh`, `next-bead.sh`
- Libraries: `lib/project-config.sh`, `lib/pane-init.sh`
- Benefit: Autonomous agent operation

**Phase 2: Workflow Hooks** (Critical for workflow enforcement)
- Scripts: 8 hooks (session, edit, bash tracking)
- Benefit: Automatic workflow rules and bead tracking

**Phase 3: Beads Integration** (Enhanced task management)
- Scripts: `br-create.sh`, `bv-claim.sh`, monitoring scripts
- Benefit: Automated bead creation and management

**Phase 4: Terminal & Fleet** (Multi-agent coordination)
- Scripts: `terminal-inject.sh`, `fleet-status.sh`, swarm coordination
- Benefit: Coordinate multiple agents in tmux

**Phase 5: Monitoring & Development** (Observability)
- Scripts: `performance-tracker.sh`, `doctor.sh`, `hook-bypass.sh`
- Benefit: System health and debugging tools

**Phase 6: Model Adapters** (Optional - if using non-Claude models)
- Scripts: `grok-claude-wrapper.sh`, `deepseek-claude-wrapper.sh`
- Benefit: Use alternative LLM providers

### All-at-Once Approach

For new projects or when doing major refactoring:

```bash
cd /path/to/AgentCore/flywheel_tools
./install.sh /path/to/your/project
```

This installs all scripts and sets up complete infrastructure.

## Prerequisites Check

Before migrating, verify:

```bash
# 1. beads_rust installed
br --version || echo "❌ Install beads_rust first"

# 2. MCP Agent Mail running
curl -s http://localhost:8765/health || echo "❌ Start Agent Mail server"

# 3. tmux available
tmux -V || echo "❌ Install tmux"

# 4. jq installed
jq --version || echo "❌ Install jq"

# 5. bash 4.0+
bash --version | head -1
```

## Phase 1: Core Infrastructure

### 1.1 Install Core Scripts

```bash
# Create directory structure
cd /path/to/your/project
mkdir -p scripts/{core,lib}

# Symlink core scripts
ln -s ~/Projects/AgentCore/flywheel_tools/scripts/core/agent-runner.sh scripts/core/
ln -s ~/Projects/AgentCore/flywheel_tools/scripts/core/wake-agents.sh scripts/core/
ln -s ~/Projects/AgentCore/flywheel_tools/scripts/core/next-bead.sh scripts/core/

# Symlink libraries
ln -s ~/Projects/AgentCore/flywheel_tools/scripts/lib/project-config.sh scripts/lib/
ln -s ~/Projects/AgentCore/flywheel_tools/scripts/lib/pane-init.sh scripts/lib/
```

### 1.2 Configure Project

Create `scripts/lib/project-config.sh` overrides if needed:

```bash
# Your project's custom configuration
export PROJECT_ROOT="$(pwd)"
export MAIL_PROJECT_KEY="$PROJECT_ROOT"

# Optional: Customize behavior
export AGENT_RUNNER_IDLE_SLEEP=60
export AGENT_RUNNER_MAX_IDLE=10
export AGENT_RUNNER_MAX_RESTARTS=5
```

### 1.3 Test Core Infrastructure

```bash
# Test agent runner (dry run)
./scripts/core/agent-runner.sh --dry-run

# Test with a bead
./scripts/core/agent-runner.sh --bead bd-test123 --dry-run

# Launch actual agent
./scripts/core/agent-runner.sh
```

**Validation**: Agent should:
1. Register with Agent Mail
2. Claim a bead from `br`
3. Launch Claude Code
4. Work autonomously

## Phase 2: Workflow Hooks

### 2.1 Install Hooks

```bash
# Create hooks directory
mkdir -p scripts/hooks

# Symlink all hooks
cd scripts/hooks
ln -s ~/Projects/AgentCore/flywheel_tools/scripts/hooks/session-start-hook.sh .
ln -s ~/Projects/AgentCore/flywheel_tools/scripts/hooks/session-stop-hook.sh .
ln -s ~/Projects/AgentCore/flywheel_tools/scripts/hooks/pre-edit-check-hook.sh .
ln -s ~/Projects/AgentCore/flywheel_tools/scripts/hooks/pre-edit-check.sh .
ln -s ~/Projects/AgentCore/flywheel_tools/scripts/hooks/pre-bash-bead-check-hook.sh .
ln -s ~/Projects/AgentCore/flywheel_tools/scripts/hooks/post-bash-bead-track-hook.sh .
ln -s ~/Projects/AgentCore/flywheel_tools/scripts/hooks/post-bead-close-hook.sh .
ln -s ~/Projects/AgentCore/flywheel_tools/scripts/hooks/pre-task-block-hook.sh .
```

### 2.2 Configure Claude Code Hooks

Add to `~/.claude/config.json`:

```json
{
  "hooks": {
    "edit": "/path/to/your/project/scripts/hooks/pre-edit-check-hook.sh",
    "bash": "/path/to/your/project/scripts/hooks/pre-bash-bead-check-hook.sh",
    "postBash": "/path/to/your/project/scripts/hooks/post-bash-bead-track-hook.sh",
    "sessionStart": "/path/to/your/project/scripts/hooks/session-start-hook.sh",
    "sessionStop": "/path/to/your/project/scripts/hooks/session-stop-hook.sh"
  }
}
```

### 2.3 Test Hooks

```bash
# Start a Claude session - should trigger session-start-hook
claude

# Try editing without a bead - should block
echo "test" > test.txt

# Create a bead first
br create "Test bead"
# Assign it
br update <bead-id> --assignee <your-agent-name>

# Now editing should work
echo "test" > test.txt
```

**Validation**: Hooks should:
1. Block edits without a bead
2. Track bash commands
3. Run session lifecycle scripts

## Phase 3: Beads Integration

### 3.1 Install Beads Scripts

```bash
mkdir -p scripts/beads

cd scripts/beads
ln -s ~/Projects/AgentCore/flywheel_tools/scripts/beads/br-create.sh .
ln -s ~/Projects/AgentCore/flywheel_tools/scripts/beads/br-start-work.sh .
ln -s ~/Projects/AgentCore/flywheel_tools/scripts/beads/br-wrapper.sh .
ln -s ~/Projects/AgentCore/flywheel_tools/scripts/beads/bv-*.sh .
ln -s ~/Projects/AgentCore/flywheel_tools/scripts/beads/log-bead-activity.sh .
ln -s ~/Projects/AgentCore/flywheel_tools/scripts/beads/bead-quality-scorer.sh .
ln -s ~/Projects/AgentCore/flywheel_tools/scripts/beads/bead-stale-monitor.sh .
```

### 3.2 Setup Work Briefs

Create `.agent-profiles/types.yaml`:

```yaml
frontend:
  name: "Frontend Development"
  constraints:
    - "Do NOT modify backend code"
    - "MUST ensure responsive design"
  approach:
    - "Read existing component patterns first"
    - "Test at multiple viewport sizes"

backend:
  name: "Backend Development"
  constraints:
    - "Do NOT modify frontend code"
    - "MUST write unit tests"
  approach:
    - "Follow repository code style"
    - "Consider backward compatibility"

# Add more types as needed
```

### 3.3 Test Beads Integration

```bash
# Create a bead with work brief
./scripts/beads/br-create.sh "Fix bug in login" --type backend

# View open beads
./scripts/beads/bv-open.sh

# Claim a bead
./scripts/beads/bv-claim.sh
```

## Phase 4: Terminal & Fleet (Optional)

Only if you need multi-agent coordination:

```bash
mkdir -p scripts/{terminal,fleet}

# Terminal integration
ln -s ~/Projects/AgentCore/flywheel_tools/scripts/terminal/*.sh scripts/terminal/

# Fleet management
ln -s ~/Projects/AgentCore/flywheel_tools/scripts/fleet/*.sh scripts/fleet/
```

## Phase 5: Monitoring & Development

### 5.1 Install Development Tools

```bash
mkdir -p scripts/{monitoring,dev}

# Monitoring scripts
ln -s ~/Projects/AgentCore/flywheel_tools/scripts/monitoring/*.sh scripts/monitoring/

# Development tools
ln -s ~/Projects/AgentCore/flywheel_tools/scripts/dev/doctor.sh scripts/dev/
ln -s ~/Projects/AgentCore/flywheel_tools/scripts/dev/hook-bypass.sh scripts/dev/
ln -s ~/Projects/AgentCore/flywheel_tools/scripts/dev/self-review.sh scripts/dev/
```

### 5.2 Run Health Check

```bash
./scripts/dev/doctor.sh
```

Expected output:
```
✅ beads_rust (br) installed
✅ Agent Mail server running
✅ tmux available
✅ jq installed
✅ Project configuration valid
✅ Scripts directory structure correct
✅ Hooks configured
```

## Phase 6: Model Adapters (Optional)

If using Grok or DeepSeek:

```bash
mkdir -p scripts/adapters/{grok,deepseek}

# Grok adapter
ln -s ~/Projects/AgentCore/flywheel_tools/scripts/adapters/grok/* scripts/adapters/grok/

# DeepSeek adapter
ln -s ~/Projects/AgentCore/flywheel_tools/scripts/adapters/deepseek/* scripts/adapters/deepseek/
```

## Migrating Existing Scripts

### Script Mapping

If you have custom agent scripts, map them to Flywheel Tools equivalents:

| Your Script | Flywheel Tools Equivalent | Notes |
|------------|---------------------------|-------|
| `start-agent.sh` | `agent-runner.sh` | Use agent-runner for autonomous operation |
| `assign-work.sh` | `bv-claim.sh` | Use beads viewer for claiming work |
| `next-task.sh` | `next-bead.sh` | Integrated with agent-runner |
| `notify-agents.sh` | `wake-agents.sh` | Wake idle agents with notifications |
| Custom hooks | Standard hooks | Merge logic into standard hooks |

### Preserving Custom Logic

If you have custom logic in existing scripts:

**Option 1: Extend Flywheel Tools Scripts**

```bash
# Create wrapper that calls Flywheel Tools + your logic
# scripts/custom-agent-runner.sh

#!/bin/bash
source scripts/lib/project-config.sh

# Your custom pre-launch logic
your_custom_setup() {
  echo "Custom setup..."
}

# Call custom setup
your_custom_setup

# Launch Flywheel Tools agent-runner
exec scripts/core/agent-runner.sh "$@"
```

**Option 2: Hook Into Workflow**

Add custom logic to hooks:

```bash
# scripts/hooks/custom-session-start.sh

#!/bin/bash

# Source Flywheel Tools hook
source "$(dirname "$0")/session-start-hook.sh"

# Add your custom logic after
your_custom_logic() {
  echo "Custom session setup..."
}

your_custom_logic
```

Update `~/.claude/config.json` to point to your custom hook.

## Configuration Migration

### Environment Variables

Map your existing environment variables:

| Old Variable | New Variable | Purpose |
|-------------|-------------|---------|
| `WORKSPACE_ROOT` | `PROJECT_ROOT` | Project root directory |
| `TASK_TRACKER_KEY` | `MAIL_PROJECT_KEY` | Agent mail project key |
| `AGENT_SLEEP_TIME` | `AGENT_RUNNER_IDLE_SLEEP` | Idle sleep duration |
| Custom vars | Keep as-is | Source in project-config.sh |

### Config Files

Consolidate configuration:

```bash
# Before: Multiple config files
config/agent.conf
config/workflow.conf
config/hooks.conf

# After: Single project-config.sh
scripts/lib/project-config.sh
```

## Testing & Validation

### Integration Test Checklist

- [ ] Agent registers with mail system
- [ ] Agent claims next bead autonomously
- [ ] Hooks block invalid operations
- [ ] Commits include bead ID prefix
- [ ] Bead closes successfully
- [ ] Agent moves to next bead
- [ ] Crash recovery works
- [ ] Wake mechanism responds
- [ ] Multi-agent coordination (if applicable)

### Test Script

Create `scripts/test-migration.sh`:

```bash
#!/bin/bash
set -e

echo "Testing Flywheel Tools Migration..."

# Test 1: Core infrastructure
echo "✓ Testing agent-runner..."
./scripts/core/agent-runner.sh --dry-run

# Test 2: Beads integration
echo "✓ Testing br-create..."
test_bead=$(./scripts/beads/br-create.sh "Test migration" --type general)

# Test 3: Hooks
echo "✓ Testing hooks..."
./scripts/hooks/session-start-hook.sh

# Test 4: Health check
echo "✓ Running doctor..."
./scripts/dev/doctor.sh

echo "✅ All tests passed!"
```

## Rollback Plan

If migration fails, rollback steps:

### 1. Disable Hooks

```bash
# Edit ~/.claude/config.json
# Remove or comment out hooks section
```

### 2. Revert to Old Scripts

```bash
# Remove symlinks
rm scripts/core/agent-runner.sh
rm scripts/hooks/*

# Restore old scripts
git checkout scripts/
```

### 3. Restore Config

```bash
# Restore old configuration
cp config/agent.conf.bak config/agent.conf
```

## Common Issues

### Issue: "command not found: br"

**Solution**: Install beads_rust:
```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/main/install.sh?$(date +%s)" | bash
```

### Issue: "Agent Mail connection failed"

**Solution**: Start Agent Mail server:
```bash
# Check if running
curl -s http://localhost:8765/health

# Start if not running
cd ~/tools/mcp_agent_mail
./scripts/start-mail-server.sh
```

### Issue: "Hook blocks all edits"

**Solution**: Verify bead context:
```bash
# Check if bead is assigned
br show <bead-id>

# Update assignee if needed
br update <bead-id> --assignee $(./scripts/agent-mail-helper.sh whoami)

# Or bypass hooks temporarily
./scripts/dev/hook-bypass.sh on
# ... do work ...
./scripts/dev/hook-bypass.sh off
```

### Issue: "Symlinks broken after repo move"

**Solution**: Re-run installer:
```bash
cd ~/Projects/AgentCore/flywheel_tools
./install.sh /path/to/your/project --force
```

### Issue: "Agent crashes immediately"

**Solution**: Check logs and configuration:
```bash
# Check agent-runner logs
tail -f /tmp/agent-runner-*.log

# Verify configuration
./scripts/dev/doctor.sh

# Test in dry-run mode
./scripts/core/agent-runner.sh --dry-run
```

## Best Practices

### 1. Start with Core Infrastructure

Don't try to migrate everything at once. Start with Phase 1, validate, then proceed.

### 2. Keep Original Scripts

Keep backups of your original scripts for reference:
```bash
mkdir -p scripts-backup
cp -r scripts/* scripts-backup/
```

### 3. Test in Staging First

If you have a staging environment, test the migration there first.

### 4. Document Custom Changes

If you customize Flywheel Tools scripts, document your changes:
```bash
# scripts/CUSTOMIZATIONS.md
```

### 5. Version Control

Commit migration progress at each phase:
```bash
git commit -m "[migration] Phase 1: Core infrastructure installed"
git commit -m "[migration] Phase 2: Hooks configured and tested"
```

## Next Steps

After successful migration:

1. **Read the documentation**
   - [Installation Guide](installation.md)
   - [Quick Start Guide](quick-start.md)

2. **Join the community**
   - Report issues on GitHub
   - Share your migration experience

3. **Optimize your workflow**
   - Tune `AGENT_RUNNER_*` settings
   - Customize work brief types
   - Set up monitoring dashboards

4. **Scale up**
   - Add more agents
   - Enable fleet coordination
   - Automate with CI/CD

## Getting Help

If you encounter issues during migration:

1. **Check the documentation**
   - [Installation Guide](installation.md)
   - [Quick Start Guide](quick-start.md)

2. **Run diagnostics**
   ```bash
   ./scripts/dev/doctor.sh
   ```

3. **Review logs**
   ```bash
   # Agent runner logs
   tail -f /tmp/agent-runner-*.log

   # Mail system logs
   curl -s http://localhost:8765/agents
   ```

4. **Ask for help**
   - GitHub Issues: Report bugs or ask questions
   - AgentCore Community: Share experiences

## Conclusion

This migration guide provides a structured approach to adopting Flywheel Tools. Follow the phased migration strategy, validate each phase, and leverage the diagnostic tools to ensure a smooth transition.

Remember:
- ✅ Start with Core Infrastructure
- ✅ Test thoroughly at each phase
- ✅ Keep backups of original scripts
- ✅ Document customizations
- ✅ Use `doctor.sh` for health checks

Good luck with your migration!
