# AgentCore Tools Wrapper Audit
**Date**: 2026-02-13
**Auditor**: OrangeLantern
**Bead**: bd-21t

## Executive Summary

The agentcore/tools/ directory contains 5 coordination script wrappers. All existing wrappers resolve correctly and have proper permissions. However, **8 coordination scripts are missing wrappers**.

## Current State

### Existing Wrappers (5 total)

All wrappers are symlinks with correct permissions and valid targets:

| Wrapper | Target | Status | Permissions |
|---------|--------|--------|-------------|
| agent-mail-helper.sh | ../../scripts/agent-mail-helper.sh | ✅ OK | Executable |
| agent-registry.sh | ../../scripts/agent-registry.sh | ✅ OK | Executable |
| auto-register-agent.sh | ../../scripts/auto-register-agent.sh | ✅ OK | Executable |
| mail-monitor-ctl.sh | ../../scripts/mail-monitor-ctl.sh | ✅ OK | Executable |
| monitor-agent-mail-to-terminal.sh | ../../scripts/monitor-agent-mail-to-terminal.sh | ✅ OK | Executable |

**Verification commands run:**
```bash
# All symlinks resolve correctly
find agentcore/tools -maxdepth 1 -type l -print | \
  while read link; do readlink -f "$link"; done
# Result: All 5 wrappers resolved successfully

# No permission issues found
find agentcore/tools -maxdepth 1 -type l ! -perm -u+x -print
# Result: No output (all wrappers are executable)
```

### lib/ Directory

The `agentcore/tools/lib/` directory exists but is empty. Per README line 176, this is reserved for "Shared utilities (future)".

## Missing Wrappers (8 total)

Based on the agentcore README (lines 56-63), coordination scripts include:
- Agent registry and mail helpers
- State monitoring and verification
- Agent coordination tools

### Gap Analysis

#### P0 - Critical Agent Coordination (6 scripts)

These scripts directly coordinate multi-agent sessions and communication:

1. **agent-control.sh**
   - **Purpose**: Interactive fzf-based agent communication interface
   - **Gap Type**: Missing wrapper
   - **Why coordination**: Direct agent-to-agent communication interface
   - **Target**: scripts/agent-control.sh (exists, executable)

2. **start-multi-agent-session.sh**
   - **Purpose**: Creates tmux session with Claude and Codex agents
   - **Gap Type**: Missing wrapper
   - **Why coordination**: Creates multi-agent sessions
   - **Target**: scripts/start-multi-agent-session.sh (exists, executable)

3. **spawn-swarm.sh**
   - **Purpose**: Launch N coordinated agents in tmux panes
   - **Gap Type**: Missing wrapper
   - **Why coordination**: Agent swarm orchestration
   - **Target**: scripts/spawn-swarm.sh (exists, executable)

4. **teardown-swarm.sh**
   - **Purpose**: Gracefully shutdown swarm agents and release resources
   - **Gap Type**: Missing wrapper
   - **Why coordination**: Agent swarm lifecycle management
   - **Target**: scripts/teardown-swarm.sh (exists, executable)

5. **broadcast-to-swarm.sh**
   - **Purpose**: Broadcast messages to agent swarms
   - **Gap Type**: Missing wrapper
   - **Why coordination**: Agent group communication
   - **Target**: scripts/broadcast-to-swarm.sh (exists, executable)

6. **visual-session-manager.sh**
   - **Purpose**: Visual session manager using fzf
   - **Gap Type**: Missing wrapper
   - **Why coordination**: Session coordination and management
   - **Target**: scripts/visual-session-manager.sh (exists, executable)

#### P1 - State Monitoring (2 scripts)

Per README line 59, "State monitoring and verification" is coordination:

7. **ntm-dashboard.sh**
   - **Purpose**: Unified NTM (Near-Term Memory) Dashboard
   - **Gap Type**: Missing wrapper
   - **Why coordination**: State monitoring dashboard
   - **Target**: scripts/ntm-dashboard.sh (exists, executable)

8. **queue-monitor.sh**
   - **Purpose**: Queue Monitor Daemon for NTM
   - **Gap Type**: Missing wrapper
   - **Why coordination**: State monitoring daemon
   - **Target**: scripts/queue-monitor.sh (exists, executable)

## Gap Classification Summary

| Gap Type | Count | Scripts |
|----------|-------|---------|
| Missing wrapper | 8 | All gaps are missing wrappers |
| Wrong target | 0 | N/A |
| Wrong permissions | 0 | N/A |
| Missing docs reference | 0 | All scripts have purpose headers |

## Verification Commands

### Commands Run

```bash
# Count coordination scripts in scripts/
find scripts/ -type f -name "*.sh" | \
  grep -E "(agent-|monitor-|mail-|registry|auto-register|swarm|session|ntm-dashboard|queue-monitor)" | \
  wc -l
# Result: 13 coordination scripts found

# List all wrappers
ls -la agentcore/tools/ | grep "^l"
# Result: 5 wrappers

# Check symlink resolution
find agentcore/tools -maxdepth 1 -type l -print | \
  while read link; do
    target=$(readlink -f "$link" 2>&1)
    if [ $? -eq 0 ] && [ -f "$target" ]; then
      echo "OK: $link -> $target"
    else
      echo "BROKEN: $link"
    fi
  done
# Result: All 5 wrappers OK

# Check executable permissions
find agentcore/tools -maxdepth 1 -type l ! -perm -u+x -print
# Result: No output (all have correct permissions)
```

## Recommendations

### Immediate Actions

1. **Create follow-up bead**: "Add missing coordination script wrappers to agentcore/tools"
   - Add 6 P0 agent coordination wrappers
   - Add 2 P1 state monitoring wrappers
   - Verify all new wrappers resolve correctly
   - Update verification scripts to check for completeness

2. **Verify no other gaps**: After adding wrappers, run comprehensive check:
   ```bash
   diff <(find scripts/ -name "*.sh" | grep -E "coordination-pattern" | sort) \
        <(find agentcore/tools -type l | xargs basename -a | sort)
   ```

### Documentation Updates Needed

The agentcore README examples (lines 64-83) should be updated to show all coordination operations, not just mail and registry.

## Files Affected

### Created
- tmp/wrapper-audit.md (this file)

### To Be Modified (in follow-up bead)
- agentcore/tools/ (add 8 new symlinks)
- agentcore/verify/check-structure.sh (update to verify completeness)

## Notes

- All existing wrappers are correctly implemented as outward symlinks (Phase 1 pattern)
- No broken symlinks found
- No permission issues found
- The gap is purely missing wrappers, not quality issues with existing ones
- All target scripts exist and are executable in scripts/ directory
