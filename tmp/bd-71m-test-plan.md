# bd-71m Performance Testing Plan

**Tester:** QuietCreek
**Date:** 2026-02-14
**Bead:** bd-71m

## Test Environment Baseline

**Current State (before tests):**
- Mail monitors running: 4
- Coordination processes: 9
- Open beads available: 0

## Test 6.1: Concurrent Agent Load Test

**Goal:** Verify 10 agents can work concurrently without lock contention

**Approach:**
1. Create 10 simple test beads
2. Spawn 10 agents simultaneously
3. Monitor lock files and claim times
4. Measure completion time
5. Check for lock contention errors

**Acceptance:** All agents complete without lock errors, reasonable claim times

**Status:** PENDING

---

## Test 6.2: Large Mail Queue Flush

**Goal:** Flush 50 notifications in < 30 seconds

**Approach:**
1. Clear current mail queues
2. Send 50 broadcast messages rapidly
3. Time the queue flush process
4. Verify all messages delivered
5. Check for data corruption

**Acceptance:** 50 messages flush in < 30s, no corruption

**Status:** IN PROGRESS

---

## Test 6.3: Long-Running Monitor Stability (24 hours)

**Goal:** Monitors stable for 24+ hours, no memory leaks

**Approach:**
1. Record baseline RSS for all monitors
2. Let monitors run for 24 hours
3. Sample RSS every hour
4. Check log file growth
5. Verify no crashes or zombies

**Acceptance:**
- RSS stable (< 10% growth)
- Logs < 100MB
- No crashes

**Status:** PENDING (requires 24h runtime)

---

## Execution Timeline

- **T+0 (now):** Execute Test 6.2 (mail queue flush)
- **T+15min:** Execute Test 6.1 (concurrent agents)
- **T+30min:** Start Test 6.3 (24h monitoring)
- **T+24h:** Complete Test 6.3 and finalize results
