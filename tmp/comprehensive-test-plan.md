# Comprehensive Agent Coordination Scripts Test Plan

## Scope
Systematically test ALL coordination scripts end-to-end to verify Phase 2 infrastructure works in production scenarios, not just isolated unit tests.

## Test Categories

### 1. Agent Lifecycle (Auto-claim & Auto-restart)
**Critical - This was reported broken by user**

**Test 1.1: Normal bead completion flow**
- Start agent in clean state
- Agent completes a bead
- Agent runs `br close BEAD-ID`
- Verify: next-bead.sh triggers automatically
- Verify: Agent claims next available bead
- Verify: Context clears (/clear executes)
- Verify: New bead prompt appears
- Verify: No manual intervention needed

**Test 1.2: No beads available scenario**
- Agent closes last available bead
- Verify: next-bead.sh detects no beads
- Verify: Agent gets "No beads available" message
- Verify: Context still clears
- Verify: Agent told to check inbox

**Test 1.3: Lock file prevents double-trigger**
- Manually create stale lock file (> 2 minutes old)
- Agent closes bead
- Verify: next-bead.sh removes stale lock and proceeds
- Create fresh lock file (< 2 minutes)
- Agent closes bead
- Verify: next-bead.sh skips (lock prevents duplicate)

**Test 1.4: Bead claim race condition**
- Two agents finish beads simultaneously
- Only one bead available
- Verify: One agent claims successfully
- Verify: Other agent gets "No beads available"
- Verify: No corruption of bead state

**Test 1.5: Context clear timing**
- Agent working on task with pending mail notifications
- Agent closes bead
- Verify: Mail queue flushed BEFORE /clear
- Verify: No notifications lost during transition

### 2. Mail Monitor Reliability
**Critical - Currently has known bug (bd-4sc)**

**Test 2.1: Monitor startup and persistence**
- Kill all monitors
- Start monitor via mail-monitor-ctl.sh
- Verify: Monitor starts and logs to correct location
- Verify: PID file created correctly
- Wait 5 minutes
- Verify: Monitor still running
- Restart tmux session
- Verify: Monitor persists (or restarts automatically)

**Test 2.2: Monitor pane resolution**
- Agent changes name (re-registration)
- Verify: Monitor detects name change
- Verify: Monitor updates tracking files
- Verify: Notifications still delivered to correct pane

**Test 2.3: Queue mechanism (when fixed)**
- Agent at CLI prompt typing
- Send mail notification
- Verify: Notification queues (not delivered immediately)
- Agent submits command (prompt clears)
- Verify: Queued notification delivers within 5s

**Test 2.4: Queue TTL and idempotency**
- Queue 3 notifications
- Wait 6 minutes (> 5 min TTL)
- Verify: Stale notifications dropped
- Queue duplicate notification (same content)
- Verify: Duplicate detected and skipped

**Test 2.5: Monitor recovery from errors**
- Kill MCP mail server
- Verify: Monitor logs error but keeps running
- Restart MCP server
- Verify: Monitor resumes checking for mail

### 3. Coordination Scripts (Canonical Paths)
**Critical - Phase 2 main deliverable**

**Test 3.1: Agent-mail-helper.sh from hostile CWDs**
- From `/`: Send mail, check inbox, whoami
- From `/tmp`: Send mail, check inbox, whoami
- From deep nested: Send mail, check inbox, whoami
- From project root: Send mail, check inbox, whoami
- Verify: All succeed with correct results

**Test 3.2: Agent-registry.sh from hostile CWDs**
- Test from same 4 CWDs as above
- Operations: list, show, register, unregister, active
- Verify: All work correctly from any CWD

**Test 3.3: All coordination scripts --help**
- For each script in agentcore/tools/:
  - Run `./agentcore/tools/SCRIPT --help`
  - Verify: Help text appears
  - Verify: No errors about missing dependencies

**Test 3.4: Symlink integrity after git operations**
- Make changes and commit
- Run git pull (simulate)
- Verify: All symlinks still valid
- Verify: No broken links in agentcore/tools/

**Test 3.5: Multi-project isolation**
- Start agent in AgentCore
- Start agent in 7D Solutions Platform  
- Send mail to each
- Verify: Messages don't cross-contaminate
- Verify: Each monitor watches correct pane
- Verify: Correct PROJECT_ROOT for each

### 4. Agent Control & Session Management

**Test 4.1: Start-multi-agent-session.sh**
- Run with N=3 agents
- Verify: 3 tmux panes created
- Verify: 3 agents registered
- Verify: 3 monitors started
- Verify: Each agent auto-registers with unique name

**Test 4.2: Agent-control.sh TUI**
- Launch agent-control.sh
- Select agent
- Send test message
- Verify: Message delivered
- Broadcast to all agents
- Verify: All receive message

**Test 4.3: Mail-monitor-ctl.sh operations**
- Test: status (shows PID and log location)
- Test: stop (kills monitor cleanly)
- Test: start (starts new monitor)
- Test: restart (stop + start)
- Verify: All operations work correctly

### 5. Error Handling & Edge Cases

**Test 5.1: Missing dependencies**
- Temporarily hide python3 from PATH
- Run coordination scripts
- Verify: Clear error message (not cryptic)
- Restore python3
- Verify: Scripts work again

**Test 5.2: Corrupt state files**
- Corrupt .beads/issues.jsonl
- Run br commands
- Verify: Error message explains issue
- Verify: No silent corruption

**Test 5.3: Network interruption**
- Disable network
- Try to send mail (MCP server unreachable)
- Verify: Clear error message
- Verify: No hang or timeout > 10s

**Test 5.4: Disk full simulation**
- Make pids/ directory read-only
- Try to start monitor
- Verify: Clear error about permissions
- Restore permissions
- Verify: Monitor starts

**Test 5.5: Stale PID files**
- Create PID file with non-existent PID
- Run mail-monitor-ctl.sh status
- Verify: Detects stale PID
- Verify: Offers to clean up

### 6. Performance & Scale

**Test 6.1: Many agents concurrently**
- Start 10 agents in parallel
- Each claims different bead
- Verify: No lock contention issues
- Verify: All beads claimed correctly

**Test 6.2: Large mail queue flush**
- Queue 50 notifications
- Make terminal idle
- Verify: All flush within reasonable time (< 30s)
- Verify: No duplicates delivered

**Test 6.3: Long-running monitor stability**
- Let monitor run for 24 hours
- Verify: Still running
- Verify: No memory leaks (RSS stable)
- Verify: Log file size reasonable (< 100MB)

## Acceptance Criteria

**Phase 2 infrastructure is production-ready when:**
- ✅ All agent lifecycle tests pass
- ✅ Mail monitors stay running reliably
- ✅ All coordination scripts work from any CWD
- ✅ Multi-project isolation verified
- ✅ Error messages clear and actionable
- ✅ No race conditions or data corruption
- ✅ Performance acceptable (no hangs/slowdowns)

## Test Execution Strategy

1. **Sequential execution required** - tests modify shared state
2. **Document all failures** - capture logs, screenshots, exact commands
3. **Test on clean slate** - reset state between test runs
4. **Real tmux environment** - no mocks/stubs for tmux operations
5. **Both projects** - run tests in AgentCore AND 7D Solutions Platform

## Dependencies

Before running tests:
- bd-4sc must be resolved (mail monitor input detection)
- All monitors stopped and restarted cleanly
- Clean .beads/ state (no in-progress beads)
- MCP mail server running
- No stale lock files in /tmp/

## Deliverables

1. **Test execution log** - timestamp, command, result for each test
2. **Failure report** - any tests that failed with debug info
3. **Verification script** - automate subset of tests for CI
4. **Production readiness report** - summary + recommendations

## Estimated Time

- Setup: 30 minutes
- Test execution: 3-4 hours (careful, methodical)
- Documentation: 1 hour
- **Total: ~5 hours**

## Notes

- This is NOT a "quick smoke test" - this is comprehensive validation
- Do NOT skip tests even if they seem redundant
- Every script mentioned in Phase 2 must be tested
- User confidence in system depends on thoroughness here
