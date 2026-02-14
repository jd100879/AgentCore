# Idle-Agent Notification Feature - Delivery Summary

**Bead**: bd-2lwz
**Date**: 2026-02-14
**Status**: ✅ Complete and Tested

---

## What Was Built

Added idle-agent notification capability to the existing `bead-stale-monitor.sh`. When agents are idle and beads are available, the system automatically sends SystemNotify messages to prompt them to claim work.

### Key Features

1. **Idle Detection**
   - Checks `/tmp/agent-bead-*.txt` tracking files
   - Treats empty/missing files as idle
   - Detects when agents claim beads (file updates)

2. **Session-Aware Agent Discovery**
   - Only notifies agents in the current project/session
   - Prevents cross-project notification spam
   - Falls back to project directory detection if not in tmux

3. **Spam Prevention**
   - 5-minute cooldown between notifications per agent
   - Tracks notifications in `.beads/agent-activity.jsonl`
   - Won't spam if no beads available or all agents busy

4. **Integration with Existing Monitor**
   - Runs in same 60-second check loop as stale-bead reminders
   - Uses same SystemNotify infrastructure
   - Same PID management and restart wrappers

---

## Testing Results

### Comprehensive Test Suite: 8/8 Tests Passing ✅

**Test Coverage:**

1. ✅ **All agents busy** - Verified no notifications sent when all agents have active beads
2. ✅ **Idle agent + beads available** - Notification sent correctly
3. ✅ **Idle agent + no beads** - No notification when work queue empty
4. ✅ **Multiple idle agents** - All idle agents notified simultaneously
5. ✅ **Spam prevention** - Cooldown blocks duplicate notifications within 5 minutes
6. ✅ **Agent claims bead** - System detects busy state after bead claimed
7. ✅ **Stale tracking files** - Empty tracking files correctly treated as idle
8. ✅ **Real-world integration** - Monitor behavior validated with actual agents

### Test Execution

```bash
./scripts/test-idle-agent-notifications.sh
```

**Results:**
- Passed: 8
- Failed: 0
- Test log: `tmp/idle-notification-test.log`

---

## Production Verification

### Monitor Status

```
✓ Monitor is running (PID: 40893)
Check interval: 60s
First reminder threshold: 900s (~15 minutes)
Escalation threshold: 1800s (~30 minutes)
Project: /Users/james/Projects/AgentCore
```

### Recent Notifications (from agent-activity.jsonl)

```
2026-02-14T14:51:38Z → FuchsiaDog
2026-02-14T14:51:38Z → OrangeLantern
2026-02-14T14:51:39Z → QuietCreek
```

Agents are receiving notifications correctly! ✓

---

## Files Modified

1. **flywheel_tools/scripts/beads/bead-stale-monitor.sh** (+160 lines)
   - Added `get_active_agents()` - Session-aware agent detection
   - Added `is_agent_idle()` - Tracking file validation
   - Added `send_idle_agent_notify()` - SystemNotify sender
   - Added `check_idle_agents()` - Main notification logic
   - Added `get_last_idle_notification()` - Cooldown tracking
   - Integrated into `monitor_beads()` main loop

2. **scripts/test-idle-agent-notifications.sh** (+716 lines)
   - Full test suite with 8 edge case tests
   - Test helpers for bead creation, agent tracking, notification counting
   - Cleanup and setup functions
   - Detailed logging and colored output

---

## How It Works

### Agent Detection

```bash
# Get agents from current tmux session only
tmux list-panes -t agentcore -F "#{@agent_name}"
```

### Idle Check

```bash
# Check tracking file
/tmp/agent-bead-TopazDeer.txt

# If missing, empty, or invalid → idle
# If contains valid bead ID → busy
```

### Notification Flow

```
Every 60 seconds:
  1. Check for open beads (br list --status open)
  2. If none → skip idle checks
  3. Get active agents (session-local)
  4. For each agent:
     - Check if idle (no/empty tracking file)
     - Check cooldown (last notification < 5min ago?)
     - Send SystemNotify if idle + cooldown expired
     - Log to agent-activity.jsonl
```

### Notification Message

```
From: SystemNotify
Subject: [System] 🎯 Beads available for work

System notice: Work is available!

Available beads: 2
Status: You are currently idle

Action: Run 'bv --robot-next' to claim the next bead

Time: 2026-02-14T14:51:38Z
Project: /Users/james/Projects/AgentCore
```

---

## Edge Cases Handled

1. **Agent in different project** - Won't receive notifications for beads they can't access
2. **Stale tracking files** - Old/empty files don't cause false "busy" state
3. **Rapid bead claiming** - Cooldown prevents notification spam
4. **Monitor restarts** - Activity log persists across restarts
5. **No agents running** - Gracefully skips idle checks
6. **No beads available** - Skips notifications, doesn't spam idle agents
7. **Mixed busy/idle agents** - Only notifies idle ones
8. **Agent claims bead during notification** - Next check detects busy state correctly

---

## Configuration

### Cooldown Period

Default: 5 minutes (300 seconds)

```bash
# In bead-stale-monitor.sh
IDLE_NOTIFICATION_COOLDOWN=300  # 5 minutes
```

### Check Interval

Default: 60 seconds (inherited from monitor configuration)

```bash
./scripts/bead-stale-monitor.sh start --interval 60
```

---

## Future Enhancements (Optional)

- [ ] Configurable cooldown via environment variable
- [ ] Priority-based notification (P0 beads notify immediately, bypass cooldown)
- [ ] Agent preferences (opt-out of idle notifications)
- [ ] Notification summary (daily digest instead of real-time)
- [ ] Multi-project support (notify agents across related projects)

---

## Commit

```
commit 83e1268
Author: James + Claude Sonnet 4.5
Date: 2026-02-14

[bd-2lwz] Add idle-agent notification to bead-stale-monitor

Features:
- Notify idle agents when open beads are available
- Session-aware agent detection (project-scoped)
- 5-minute cooldown to prevent spam
- Activity logging to agent-activity.jsonl

Testing:
- Comprehensive test suite with 8 edge cases
- All tests passing (8/8)
```

---

## Conclusion

✅ **Feature delivered, tested, and verified in production.**

The idle-agent notification system is now live and actively notifying agents when work becomes available. All edge cases are covered, spam prevention is working, and the system integrates seamlessly with existing monitoring infrastructure.

**Ready for production use!**
