# Flywheel Tools Migration Status

**Last Updated**: 2026-02-10
**Epic**: bd-11fw - AgentCore Migration - Flywheel Tools Component
**Status**: In Progress - Phase 1

## Overview

Flywheel Tools is being migrated from `agent-flywheel-integration` to `AgentCore` to create a reusable, standalone component. This migration consolidates ~68 shell scripts into a clean, documented package that other projects can adopt.

## Migration Phases

### ✅ Phase 0: Setup & Planning (Complete)

**Beads**: bd-11fw.1 - Verify duplicates and create directory structure

- [x] bd-11fw.1.1: Create AgentCore/flywheel_tools directory structure
- [x] bd-11fw.1.2: Create flywheel_tools README.md and documentation
- [ ] bd-11fw.1.3: Create install.sh script for flywheel_tools

**Status**: 2/3 complete (67%)
**Owner**: DustyHeron, TurquoiseGrove

### ⏳ Phase 1: Core Agent Infrastructure (In Progress)

**Bead**: bd-11fw.2 - Migrate core agent infrastructure

**Scripts to migrate** (12 total):
- [ ] lib/project-config.sh (PRIORITY: HIGH - used by 40+ scripts)
- [ ] lib/pane-init.sh (used by agent-runner.sh)
- [ ] agent-runner.sh
- [ ] wake-agents.sh
- [ ] next-bead.sh
- [ ] session-start-hook.sh
- [ ] session-stop-hook.sh
- [ ] pre-edit-check-hook.sh
- [ ] pre-edit-check.sh
- [ ] pre-bash-bead-check-hook.sh
- [ ] post-bash-bead-track-hook.sh
- [ ] post-bead-close-hook.sh
- [ ] pre-task-block-hook.sh

**Status**: 0/13 complete (0%)
**Owner**: DustyHeron
**Blockers**: None

**Critical Path**: lib/project-config.sh MUST be migrated first before any other scripts.

### 📋 Phase 2: Beads Integration (Planned)

**Bead**: bd-11fw.3 - Migrate beads workflow automation

**Scripts to migrate** (11 total):
- [ ] br-create.sh
- [ ] br-start-work.sh
- [ ] br-wrapper.sh
- [ ] bv-all-open.sh
- [ ] bv-all.sh
- [ ] bv-claim.sh
- [ ] bv-open.sh
- [ ] bv-sync.sh
- [ ] log-bead-activity.sh
- [ ] bead-stale-monitor.sh
- [ ] bead-quality-scorer.sh

**Status**: 0/11 complete (0%)
**Owner**: RoseFinch
**Blocks**: Phase 1 must complete first

### 📋 Phase 3: Terminal & Fleet Management (Planned)

**Bead**: bd-11fw.4 - Migrate terminal & fleet management

**Scripts to migrate** (11 total):
- [ ] arrange-panes.sh
- [ ] cleanup-after-pane-removal.sh
- [ ] renumber-panes.sh
- [ ] terminal-inject.sh
- [ ] fleet-core.sh
- [ ] fleet-metrics.sh
- [ ] fleet-status.sh
- [ ] fleet-tmux-status.sh
- [ ] assign-tasks.sh
- [ ] swarm-metrics.sh
- [ ] swarm-status.sh

**Status**: 0/11 complete (0%)
**Owner**: RoseFinch

### 📋 Phase 4: Monitoring & Metrics (Planned)

**Bead**: bd-11fw.5 - Migrate monitoring & metrics

**Scripts to migrate** (6 total):
- [ ] expiry-notify-monitor.sh
- [ ] reservation-metrics.sh
- [ ] reservation-status.sh
- [ ] metrics-summary.sh
- [ ] search-metrics.sh
- [ ] performance-tracker.sh (verify not duplicate)

**Status**: 0/6 complete (0%)
**Owner**: RoseFinch

### 📋 Phase 5: Development Tools & Adapters (Planned)

**Bead**: bd-11fw.6 - Migrate development tools & analysis

**Scripts to migrate** (19 total):
- [ ] doctor.sh
- [ ] hook-bypass.sh
- [ ] self-review.sh
- [ ] search-history.sh
- [ ] summarize-session.sh
- [ ] validate-agent-session.sh
- [ ] generate-task-graph.sh
- [ ] task-analyzer.sh
- [ ] task-lifecycle-tracker.sh
- [ ] file-picker.sh
- [ ] visual-session-manager.sh
- [ ] ntm-dashboard.sh
- [ ] launcher.sh
- [ ] grok-claude-wrapper.sh
- [ ] deepseek-claude-wrapper.sh
- [ ] setup-codex-oauth.sh
- [ ] macro-helpers.sh
- [ ] start-mail-server.sh
- [ ] stop-mail-server.sh

**Status**: 0/19 complete (0%)
**Owner**: DustyHeron

### 📋 Phase 6: Cleanup, Documentation & Testing (Planned)

**Bead**: bd-11fw.7 - Cleanup, documentation & testing

**Tasks**:
- [ ] bd-11fw.7.1: Verify and remove duplicate scripts from agent-flywheel-integration
- [ ] bd-11fw.7.2: Update AgentCore README.md and ARCHITECTURE.md
- [ ] bd-11fw.7.3: Create migration guide for projects adopting flywheel_tools
- [ ] bd-11fw.7.4: Archive deprecated scripts to deprecated/ directory
- [ ] bd-11fw.7.5: Migrate unit tests to AgentCore/flywheel_tools/tests/
- [ ] bd-11fw.7.6: Document integration test patterns for projects
- [ ] bd-11fw.7.7: End-to-end integration testing of migrated components

**Status**: 0/7 complete (0%)
**Owner**: DustyHeron

## Overall Progress

**Total Scripts**: 68 core scripts + documentation
- **Migrated**: 0 scripts (0%)
- **In Progress**: 2 documentation tasks
- **Remaining**: 68 scripts

**Total Beads**: 43 (1 epic + 7 phase beads + 35 subtasks)
- **Complete**: 2 beads
- **In Progress**: 1 bead
- **Remaining**: 40 beads

## Timeline Estimate

**Original Plan**: 3 weeks
- **Week 1**: Phase 0-1 (setup + core infrastructure)
- **Week 2**: Phase 2-4 (beads + terminal + monitoring)
- **Week 3**: Phase 5-6 (dev tools + cleanup + testing)

**Current Status**: Week 1, Day 1

## Dependencies

### Critical Dependencies (Block All Work)

1. **lib/project-config.sh**: Used by 40+ scripts
   - Must migrate first in Phase 1
   - Provides: $PROJECT_ROOT, $PIDS_DIR, common functions

2. **lib/pane-init.sh**: Used by agent-runner.sh
   - Must migrate early in Phase 1
   - Provides: Pane initialization, identity detection

### Phase Dependencies

- **Phase 2** blocks on **Phase 1**: Beads scripts depend on lib/ and hooks
- **Phase 3-5** can run in parallel after Phase 1
- **Phase 6** blocks on all other phases

## Already Migrated Components

These scripts were previously migrated to AgentCore (not part of flywheel_tools):

- agent-control.sh
- agent-mail-helper.sh
- agent-registry.sh
- auto-register-agent.sh
- auto-scaler.sh
- broadcast-to-swarm.sh
- file-picker.sh (may need to move to flywheel_tools)
- launcher.sh
- mail-monitor-ctl.sh
- monitor-agent-mail-to-terminal.sh
- performance-tracker.sh (verify not duplicate)
- plan-to-agents.sh
- queue-monitor.sh
- reserve-files.sh
- spawn-swarm.sh
- start-multi-agent-session.sh
- teardown-swarm.sh
- visual-session-manager.sh (may need to move to flywheel_tools)

## Known Issues

### Duplicate Scripts

Several scripts exist in both repositories. These need verification:

- **performance-tracker.sh**: In both AgentCore and agent-flywheel-integration
- **file-picker.sh**: Already in AgentCore, but listed for flywheel_tools migration
- **launcher.sh**: Already in AgentCore, but listed for flywheel_tools migration

**Resolution**: bd-11fw.7.1 will audit and remove duplicates

### Path Dependencies

Many scripts use relative paths like `../scripts/` or `$SCRIPT_DIR/`. After migration:

- Update paths to use $PROJECT_ROOT
- Ensure symlinks resolve correctly
- Test from different working directories

### Model Adapter Complexity

Grok and DeepSeek adapters include:
- Wrapper scripts
- Patched node_modules
- Configuration files
- OAuth setup scripts

These need careful migration to preserve patches.

## Testing Strategy

### Unit Tests (Phase 6)

Migrate existing tests from agent-flywheel-integration/tests/:
- Hook tests
- Script argument parsing tests
- Configuration loading tests

### Integration Tests (Phase 6)

Test complete workflows:
1. Agent runner lifecycle (claim → work → close → repeat)
2. Multi-agent coordination (messages + reservations)
3. Hook enforcement (pre-edit, post-bash, etc.)
4. Fleet management (status, metrics, assignment)

### Smoke Tests (Continuous)

After each phase:
```bash
# Verify scripts are executable
find scripts/ -type f -name "*.sh" -exec test -x {} \; || echo "Non-executable scripts found"

# Check for missing dependencies
./scripts/doctor.sh

# Verify hooks install correctly
./install.sh /tmp/test-project
cd /tmp/test-project && br init && ./scripts/doctor.sh
```

## Rollback Plan

If migration issues arise:

1. **Keep agent-flywheel-integration intact** during migration
2. Projects can continue using original scripts
3. Switch to flywheel_tools only after Phase 6 complete
4. Symlinks allow gradual adoption (per-script basis)

## Success Criteria

Migration is complete when:

- [x] All 68 scripts migrated to flywheel_tools/
- [x] install.sh creates working project setup
- [x] All hooks functional and tested
- [x] Documentation complete (README + guides)
- [x] Unit tests passing
- [x] Integration tests passing
- [x] At least one external project adopted flywheel_tools
- [x] Duplicate scripts removed from agent-flywheel-integration
- [x] Migration guide published

## Resources

- **Epic Bead**: bd-11fw (agent-flywheel-integration)
- **Phase Beads**: bd-11fw.1 through bd-11fw.7
- **Docs**: [docs/bead-expansion-summary.md](../../agent-flywheel-integration/docs/bead-expansion-summary.md)
- **Original Plan**: [docs/agentcore-migration-plan.md](../../agent-flywheel-integration/docs/agentcore-migration-plan.md)

## Contact

- **RoseFinch**: Phases 2-4 (beads, terminal, monitoring)
- **DustyHeron**: Phases 1, 5-6 (core, dev tools, cleanup)
- **Epic Coordination**: Both agents

---

*This document is updated as phases complete. Check git history for detailed changes.*
