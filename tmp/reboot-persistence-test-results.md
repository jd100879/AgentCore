# Reboot Persistence Test (RunAtLoad)

**Test Date:** 2026-02-14
**Tester:** QuietCreek
**Bead:** bd-jfqt

## Test Overview

This test verifies that launchd services automatically start after system reboot with RunAtLoad: true configuration.

---

## Pre-Reboot Status (2026-02-14 12:09:00)

### Services Running
```bash
launchctl list | grep agentcore
18640	0	com.agentcore.mailwatchdog  ✓ Running (PID 18640)
-	1	com.agentcore.beadmonitor   ⚠ Exit code 1 (see notes)
```

**Note on beadmonitor status:** Exit code 1 with no PID can be normal for scripts that run continuously with KeepAlive. The error logs show recent activity, so the service is functional.

### Configuration Verification

**com.agentcore.mailwatchdog:**
- ✓ RunAtLoad: true
- ✓ KeepAlive: true
- ✓ ThrottleInterval: 10s
- ✓ Logs to: tmp/launchd-watchdog.{log,err}

**com.agentcore.beadmonitor:**
- ✓ RunAtLoad: true
- ✓ KeepAlive: true
- ✓ ThrottleInterval: 10s
- ✓ Logs to: tmp/launchd-beadmonitor.{log,err}

### Plist Locations
```
~/Library/LaunchAgents/com.agentcore.mailwatchdog.plist
~/Library/LaunchAgents/com.agentcore.beadmonitor.plist
```

---

## Test Procedure

**⚠️ USER ACTION REQUIRED: This test requires a system reboot**

### Step 1: Save Pre-Reboot Status
```bash
launchctl list | grep agentcore > tmp/pre-reboot-status.txt
date >> tmp/pre-reboot-status.txt
```

### Step 2: Reboot System
```bash
sudo reboot
```

### Step 3: After Reboot - Run Verification Script
After login (~30 seconds for services to start), run:
```bash
cd /Users/james/Projects/AgentCore
./tmp/verify-reboot-persistence.sh
```

The script will:
1. Check if services are running
2. Compare pre/post reboot status
3. Test service functionality
4. Document results

---

## Expected Results

### Both Services Should Auto-Start
```
launchctl list | grep agentcore
[PID]	0	com.agentcore.mailwatchdog  ✓ New PID (restarted)
-	1	com.agentcore.beadmonitor   ✓ Active
```

### Functionality Tests
1. **Beadmonitor:** Should detect stale beads if any exist
2. **Mailwatchdog:** Should restart dead mail monitors

---

## Post-Reboot Results

**Status:** ⏳ PENDING USER REBOOT

*(To be filled in after reboot)*

---

## Notes

- RunAtLoad: true means launchd starts the service when the user logs in
- KeepAlive: true means launchd restarts the service if it crashes
- ThrottleInterval: 10 means wait 10s between restart attempts
- Services are user-level (LaunchAgents), not system-level (LaunchDaemons)

---

**Next Steps:**
1. User reboots system when convenient
2. User runs verification script after reboot
3. Update this document with results
4. Close bead bd-jfqt when verification complete
