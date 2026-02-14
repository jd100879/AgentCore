# BD-2XB6 Investigation Summary

## Problem
Agents getting stuck after closing beads. Lock files aging to 300+ seconds with no next-bead.sh processes running.

## Root Cause Identified
**Critical Design Flaw:** Lock file created in foreground process (line 26), but cleanup delegated to separate disowned background process (trap at line 163).

**Why it failed:**
- Background process killed by SIGKILL (OOM killer, user action, resource limits)
- Trap cannot catch SIGKILL → lock never cleaned up
- Lock age (300s+) exceeded max runtime (223s) proving process was killed, not hung

## Solution Implemented (bd-2xb6.1)

### Three-Layer Defense
1. **Foreground trap** (line 30) - Cleans lock on ANY exit path
2. **Stale lock auto-cleanup** (lines 20-24) - Self-healing recovery  
3. **Background trap** (retained, line 163) - Original cleanup mechanism

### Code Changes
```bash
# Added after lock creation (line 30):
trap "rm -f '$LOCK_FILE'" EXIT

# Added stale lock check (lines 20-24):
if [ "$lock_age" -gt 240 ]; then
    echo "Cleaning stale lock (age: ${lock_age}s)"
    rm -f "$LOCK_FILE"
```

## Testing
- ✅ Foreground trap fires on early exit
- ✅ Background trap still works (disowned processes)
- ✅ Stale lock cleanup logic correct
- ✅ No regression in normal operation

## Files Modified
- `flywheel_tools/scripts/core/next-bead.sh`
- `scripts/next-bead.sh` (symlink to above)

## Status
✅ **RESOLVED** - Committed in bd-2xb6.1
