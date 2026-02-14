# bd-2xb6 Test Plan: Lock Cleanup Verification

## Test Objective
Verify that the lock file is properly removed by the background process after bead transition.

## Test Setup

1. **Monitor script** to watch lock file lifecycle:

```bash
#!/usr/bin/env bash
# watch-lock.sh - Monitor next-bead.sh lock file lifecycle

pane_id="${TMUX_PANE:-%0}"
lock_file="/tmp/next-bead-${pane_id}.lock"

echo "Monitoring lock file: $lock_file"
echo "Press Ctrl+C to stop"
echo ""

while true; do
    if [ -f "$lock_file" ]; then
        age=$(( $(date +%s) - $(stat -f %m "$lock_file" 2>/dev/null || echo 0) ))
        echo "[$(date +%H:%M:%S)] LOCK EXISTS - Age: ${age}s"
    else
        echo "[$(date +%H:%M:%S)] No lock file"
    fi
    sleep 2
done
```

## Test Procedure

### Part 1: Verify Lock Creation and Cleanup

1. Create a test bead:
   ```bash
   br create "Test bead for bd-2xb6 verification" \
     --description "Dummy bead to test next-bead.sh lock cleanup" \
     --priority 3
   ```

2. In a separate terminal window, start the monitor:
   ```bash
   bash tmp/watch-lock.sh
   ```

3. Claim and immediately close the test bead:
   ```bash
   test_id=$(br create "Test bead" --priority 3 --format json | jq -r .id)
   br update "$test_id" --status in_progress --owner QuietCreek
   # Work on it (just echo something)
   echo "Test work complete"
   br close "$test_id"
   ./scripts/next-bead.sh
   ```

4. **Expected behavior:**
   - Monitor shows "LOCK EXISTS" shortly after next-bead.sh runs
   - Lock age increases: 2s, 4s, 6s, 8s, etc.
   - After ~15-20s (background process duration), monitor shows "No lock file"
   - Lock never exceeds ~25s

5. **Failure indicators:**
   - Lock age exceeds 60s
   - Lock persists after 2+ minutes
   - Monitor shows "LOCK EXISTS" indefinitely

### Part 2: Verify Multiple Transitions

Repeat Part 1 three times to ensure consistent cleanup:

```bash
for i in {1..3}; do
  test_id=$(br create "Test bead $i" --priority 3 --format json | jq -r .id)
  br update "$test_id" --status in_progress --owner QuietCreek
  br close "$test_id"
  ./scripts/next-bead.sh
  sleep 30  # Wait for background process

  # Check for stale locks
  lock_count=$(ls /tmp/next-bead-*.lock 2>/dev/null | wc -l)
  echo "Stale locks after iteration $i: $lock_count"
done
```

**Expected:** `lock_count` should be 0 after each iteration.

### Part 3: Verify Cleanup on Failure

Test that lock is removed even if background process encounters an error:

1. Temporarily break terminal-inject.sh (make it exit 1)
2. Run next-bead.sh
3. Verify lock is still removed (trap catches the failure)

## Success Criteria

✅ Lock file appears when next-bead.sh runs
✅ Lock file is removed within 25 seconds
✅ No stale locks accumulate after multiple transitions
✅ Lock cleanup works even on background process failure
✅ Background process still completes its job (/clear + prompt injection)

## Failure Scenarios

❌ Lock persists beyond 60 seconds
❌ Multiple stale locks accumulate
❌ Lock cleanup prevents normal background operation
❌ Trap interferes with prompt injection

## Rollback Plan

If the fix causes issues:

```bash
# Revert the commit
git revert bffa446

# Or manually remove the trap line
# Edit flywheel_tools/scripts/core/next-bead.sh
# Remove line 163: trap "rm -f '$LOCK_FILE'" EXIT
```

## Additional Notes

- The trap ensures cleanup even if the background process is killed (SIGTERM)
- The trap does NOT prevent signals from propagating (bash default)
- Lock removal happens at subshell exit, which is after all commands complete
- This fix does not change the timing of prompt injection or /clear behavior
