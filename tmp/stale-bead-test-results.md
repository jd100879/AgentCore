# Stale Bead Notification Test Results

## Test Setup

**Test Bead:** bd-3awq ("TEST: Stale detection test bead")
**Claimed By:** OrangeLantern
**Claim Time:** 2026-02-14 17:58:16 UTC
**Expected Trigger:** ~18:13:16 UTC (15 minutes after claim)
**Verification Window:** 18:13-18:30 UTC

## Test Procedure

1. ✅ Created test bead with clear test marker in title
2. ✅ Claimed bead to start stale timer (status: in_progress)
3. ⏳ **WAITING** - Must remain idle for 16+ minutes
4. ⏳ Check for stale notification via agent mail
5. ⏳ Verify notification contents

## Launchd Monitor Status

Check monitor is running:
```bash
launchctl list | grep beadmonitor
```

Expected output: Should show com.agentcore.beadmonitor with PID

## How to Verify Results

After 18:13 UTC, run:
```bash
./scripts/agent-mail-helper.sh inbox | grep -i stale
```

Expected notification should contain:
- Bead ID: bd-3awq
- Agent name: OrangeLantern
- Stale threshold: 15 minutes
- Current duration: 16+ minutes

## Test Status

**Status:** ❌ **BLOCKED - BUG DISCOVERED**
**Updated By:** QuietCreek
**Update Time:** 2026-02-14 11:58 PST

## 🐛 Critical Bug Found

### Issue
Monitor script **CANNOT DETECT in-progress beads** due to field name mismatch.

**File:** `flywheel_tools/scripts/beads/bead-stale-monitor.sh:296`

```bash
owner=$(echo "$beads_json" | jq -r ".[$i].assignee")
```

**Problem:** Script looks for `.assignee` field, but beads JSON schema uses `created_by`.

**Evidence from monitor logs:**
```
Checking for stale beads (threshold: 900s)...
No beads in progress.
```

Yet `br list --status=in_progress` shows: bd-1tko, bd-3awq

**Root Cause:** When `owner` is null (line 296), script skips the bead entirely (line 298-300).

### Available Fields in Beads JSON
```
compaction_level, created_at, created_by, dependency_count, dependent_count,
description, id, issue_type, original_size, priority, source_repo, status,
title, updated_at
```

Note: No `assignee` field exists!

### Proposed Fix

Change line 296 to:
```bash
owner=$(echo "$beads_json" | jq -r ".[$i].created_by")
```

### Impact

- ❌ Stale bead notifications **will never be sent** until this is fixed
- ❌ Test bd-3awq will NOT trigger notification (monitor can't see it)
- ❌ All in-progress beads are invisible to monitor

## Next Steps

1. **Create new bead** to fix monitor script (line 296)
2. **Re-run stale detection test** after fix is deployed
3. **Verify launchd picks up the fix** (may need reload)

## Notes

- Monitor runs every 60 seconds (checked daemon config)
- 15-minute stale threshold is 900 seconds
- Monitor IS running (PID 27628) but cannot detect beads
- No other activity on bd-3awq during waiting period (preserves stale state)

---

**Test cannot proceed until bug is fixed. Marking bd-1tko as blocked.**

---

## 🔍 Additional Investigation by OrangeLantern (2026-02-14 12:05 PST)

### Correction to QuietCreek's Analysis

The `assignee` field **DOES exist** in the JSON schema, but it's **null** when beads are claimed without explicitly setting it.

**Verified:**
```bash
$ br list --status in_progress --format json | jq '.[0] | keys'
[
  "assignee",  # ← Field exists!
  "compaction_level",
  "created_at",
  "created_by",
  ...
]
```

**Value check:**
```bash
$ br list --status in_progress --format json | jq '.[0] | {assignee, owner, created_by}'
{
  "assignee": null,  # ← Problem: null when using --status=in_progress
  "owner": null,
  "created_by": "james"
}
```

### Root Cause Analysis

**Two bugs working together:**

1. **Claiming beads incorrectly:** Using `br update bd-xxx --status=in_progress` doesn't set assignee
   - **Correct method:** `br update bd-xxx --claim` (atomic: assignee + status)
   - **Or manually:** `br update bd-xxx --status=in_progress --assignee=AgentName`

2. **Monitor script assumes assignee is set:** Line 296 expects non-null assignee
   - Script skips beads with null owner (lines 298-300)
   - Should handle null assignee gracefully

### Bugs Fixed During Investigation

#### ✅ Bug #1: Missing PATH in launchd plist
- **Problem:** `br` command not in PATH for launchd daemon
- **Fix:** Added EnvironmentVariables to plist:
  ```xml
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/Users/james/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  ```
- **Verified:** `br list` now works with limited PATH
- **Location:** tmp/com.agentcore.beadmonitor.plist (updated and installed)

#### ✅ Bug #2: Test beads not properly claimed
- **Problem:** bd-1tko and bd-3awq had null assignee
- **Fix:** Set assignee manually:
  ```bash
  br update bd-1tko --assignee OrangeLantern
  br update bd-3awq --assignee OrangeLantern
  ```
- **Status:** Both beads now have assignee set

### Current Blockers

#### ❌ Bug #3: Monitor daemon crashed
- **Symptom:** launchctl shows exit code -9 (SIGKILL)
- **PID 27628:** Process no longer exists
- **Last start:** Sat Feb 14 11:48:42 CST 2026
- **Issue:** launchctl unload/load didn't restart cleanly
- **Impact:** Monitor not running, cannot test stale detection

### Next Steps to Unblock Test

1. **Restart monitor daemon:**
   ```bash
   launchctl bootout gui/$(id -u)/com.agentcore.beadmonitor || true
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.agentcore.beadmonitor.plist
   ```

2. **Verify monitor detects beads:**
   ```bash
   # Wait 60 seconds for first check cycle
   tail -f tmp/launchd-beadmonitor.log
   # Should show "Found X beads in progress" not "No beads"
   ```

3. **Document proper claim workflow:**
   - Update AGENTS.md to recommend `br update --claim`
   - Or at minimum `br update --status=in_progress --assignee=AgentName`

4. **Consider monitor improvements:**
   - Handle null assignee gracefully (use "unknown" or skip notification?)
   - Log warning when beads have null assignee
   - Add health check endpoint/log

### Test Bead Status
- **bd-1tko:** CLOSED (not in progress anymore)
- **bd-3awq:** IN_PROGRESS with assignee=OrangeLantern (ready for test)
