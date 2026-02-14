# bd-2xb6 Investigation Findings

**Date:** 2026-02-14
**Agent:** QuietCreek
**Issue:** next-bead.sh background process leaves stale lock files

## Evidence

### Stale Lock File Found
```
-rw-r--r--@ 1 james  wheel  0 Feb 14 07:54 /tmp/next-bead-%157.lock
Lock created: 2026-02-14 07:54:01
Age: 363s (way past 120s threshold)
```

### No Background Processes Running
```
$ ps aux | grep -E "next-bead|terminal-inject" | grep -v grep
(no results)
```

**Conclusion:** Background process completed but lock file was never removed.

## Root Cause

**Location:** `scripts/next-bead.sh:161-199`

**The bug:** Lock file created by main script (line 26) is never removed by background process.

### Execution Flow
1. **Line 26:** Main script creates lock: `touch "$LOCK_FILE"`
2. **Lines 161-196:** Main script launches background process with `( ... ) &`
3. **Line 197:** Main script calls `disown`
4. **Line 199:** Main script **exits immediately** (lock still exists)
5. **Background process:** Runs independently (interrupt, wait, /clear, send prompt)
6. **Background completes:** Lock is never removed

### Current Lock Cleanup (Only in Main Script)
- **Line 65:** If claim verification fails (before background starts)
- **Line 91:** If NO_CLEAR is set (before background starts)

**Neither of these cases covers normal background process completion.**

## The Fix

Add lock cleanup to the background process using a trap:

```bash
# Background: interrupt agent, wait for idle, send /clear, then send new bead assignment
(
    # Ensure lock cleanup on exit (success or failure)
    trap "rm -f '$LOCK_FILE'" EXIT

    # Interrupt the agent if it's still working (Escape stops current operation)
    "$SCRIPT_DIR/terminal-inject.sh" --keys "Escape"
    sleep 2

    # ... rest of background process ...
) &
disown
```

**Why this works:**
- `trap "rm -f '$LOCK_FILE'" EXIT` ensures cleanup happens when subshell exits
- Works even if background process crashes/fails
- Lock removed automatically when process completes normally
- Main script can still exit immediately after `disown`

## Verification Plan

1. Apply the fix
2. Create a test bead
3. Close the test bead (triggers next-bead.sh)
4. Monitor lock file creation and removal
5. Verify lock is removed within ~15-20s (duration of background process)
6. Confirm no stale locks remain after completion

## Impact

**Before fix:**
- Every successful bead transition creates a permanent stale lock
- Agents see "Transition already in progress" for 2+ minutes
- After 120s, old lock is ignored and new transition starts
- Multiple stale locks accumulate in /tmp

**After fix:**
- Lock removed automatically when background process completes
- No stale locks accumulate
- Clean state after every transition
- More reliable agent lifecycle
