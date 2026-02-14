# Watchdog Mail Monitor Restart Test

**Test Date:** 2026-02-14
**Tester:** QuietCreek
**Bead:** bd-3jpk

## Test Setup

**Target Agent:** TopazDeer
**Original PID:** 91537
**Original Process:**
```
james  91537  0.0  0.0 435308000 2496  ??  S  10:38AM  0:02.13
/bin/bash /Users/james/Projects/AgentCore/scripts/monitor-agent-mail-to-terminal.sh TopazDeer
```

**Test Plan:**
1. Kill TopazDeer's mail monitor (PID 91537) with `kill -9`
2. Wait 60 seconds
3. Verify watchdog restarted the monitor (new PID should appear)
4. Send test mail to TopazDeer to verify functionality
5. Confirm TopazDeer receives the notification

---

## Test Execution

### Step 1: Kill the Monitor Process
**Time:** 2026-02-14 12:04:13
**Command:** `kill -9 91537`
**Result:** ✓ Process killed successfully

**Verification:**
```bash
ps aux | grep 'monitor-agent-mail-to-terminal.sh' | grep TopazDeer
# (no output - process confirmed dead)
```

---

### Step 2: Wait for Watchdog Detection
**Wait Time:** 90 seconds total (3 check cycles at 30s interval)
**Watchdog Check Times:**
- First check: ~12:04:43 (30s after kill)
- Second check: ~12:05:13 (60s after kill)
- Third check: ~12:05:43 (90s after kill)

**Watchdog Status:**
```bash
launchctl list | grep mailwatchdog
# 18640	0	com.agentcore.mailwatchdog (running ✓)
```

**Watchdog Log:**
```
[Sat Feb 14 11:29:38 CST 2026] Mail monitor watchdog started (check interval: 30s)
[Sat Feb 14 11:45:57 CST 2026] Mail monitor watchdog started (check interval: 30s)
# No restart messages for TopazDeer!
```

---

### Step 3: Verify Monitor Restart Status
**Time:** 2026-02-14 12:07:24 (3 minutes after kill)
**Result:** ✗ Monitor was NOT restarted

```bash
ps aux | grep 'monitor-agent-mail-to-terminal.sh' | grep TopazDeer
# (no output - still dead)
```

---

## Root Cause Analysis

### Bug Discovered: Field Name Mismatch

The watchdog script (`scripts/mail-monitor-watchdog.sh`) looks for `.agent_name` in identity files:

```bash
# Line 22 of mail-monitor-watchdog.sh:
agent_name=$(jq -r '.agent_name // empty' "$identity_file" 2>/dev/null)
```

However, ALL identity files use `.agent_mail_name` instead:

```json
// Example: panes/agentcore-1-2.identity (TopazDeer)
{
  "pane": "agentcore:1.2",
  "name": "Claude 2",
  "type": "claude-code",
  "agent_mail_name": "TopazDeer"  // ← Field is agent_mail_name, not agent_name
}
```

**Impact:** The watchdog extracts `null` for every agent, then skips them due to the check:
```bash
if [ -n "$agent_name" ] && [ "$agent_name" != "null" ]; then
```

**Result:** Watchdog runs but never detects or restarts ANY dead monitors.

---

## Test Results Summary

| Test Item | Expected | Actual | Status |
|-----------|----------|--------|--------|
| Watchdog running | Running | Running (PID 18640) | ✓ PASS |
| Check interval | 30s | 30s | ✓ PASS |
| Detect dead monitor | Yes | No | ✗ FAIL |
| Restart monitor | Yes | No | ✗ FAIL |
| Log restart action | Yes | No logs | ✗ FAIL |

---

## Findings

### What Works ✓
1. **Watchdog service:** Launchd keeps watchdog running with KeepAlive
2. **Check loop:** Watchdog checks every 30 seconds as configured
3. **Tmux integration:** Watchdog correctly scans panes in project directory
4. **Identity file detection:** Watchdog finds and reads `.identity` files

### What's Broken ✗
1. **Field name mismatch:** Watchdog looks for `.agent_name` but files use `.agent_mail_name`
2. **Zero agents monitored:** Due to mismatch, watchdog monitors 0 agents (should be 4+)
3. **No restart functionality:** Dead monitors are never detected or restarted

---

## Verification Data

### Active Agents in AgentCore
```
panes/agentcore-1-1.identity → OrangeLantern
panes/agentcore-1-2.identity → TopazDeer
panes/agentcore-1-3.identity → QuietCreek
panes/agentcore-1-4.identity → FuchsiaDog
panes/bridge-1-1.identity    → RainyMarsh
```

### Monitors That Should Be Protected
All 5 agents above have mail monitors that should be auto-restarted if killed.

---

## Recommendations

1. **Fix field name:** Update `mail-monitor-watchdog.sh` line 22:
   ```bash
   # Change from:
   agent_name=$(jq -r '.agent_name // empty' "$identity_file" 2>/dev/null)
   # To:
   agent_name=$(jq -r '.agent_mail_name // empty' "$identity_file" 2>/dev/null)
   ```

2. **Add validation:** Watchdog should log how many agents it found on each check cycle

3. **Add restart count:** Track how many restarts happened (for monitoring)

4. **Re-test:** After fix, repeat this test to verify restart works

---

**Test Completed:** 2026-02-14 12:08:00
**Tester:** QuietCreek
**Outcome:** Test revealed critical bug preventing watchdog from functioning
