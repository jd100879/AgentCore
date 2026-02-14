# Test Plan for bd-4sc: Mail Monitor Input Detection Fix

## Changes Made

### 1. Added Configuration Variables
- `MAIL_BUSY_WINDOW_SEC` (default: 12) - Consider pane "busy" if activity within last N seconds
- `MAIL_REQUIRE_PANE_ACTIVE` (default: 1) - Only queue if pane is active

### 2. Implemented `is_pane_busy_for_notifications()`
Comprehensive detection using three signals:
1. **`#{pane_last_activity}`** - Primary signal (detects typing & streaming output)
2. **`#{pane_in_mode}`** - Detects copy-mode/scrollback
3. **`has_pending_input()`** - Backward compatibility for CLI prompt detection

### 3. Updated Function Calls
- `send_to_terminal()` - Now uses `is_pane_busy_for_notifications()`
- Queue flush logic - Now uses `is_pane_busy_for_notifications()`

## Test Scenarios

### Scenario 1: Idle at CLI Prompt
**Setup:** Agent idle at `❯` prompt, no typing for > 12 seconds
**Expected:** Mail notification delivers immediately
**Test:**
```bash
# Send test mail while agent is idle
$PROJECT_ROOT/scripts/agent-mail-helper.sh send OrangeLantern "Test: Idle prompt"
# Check monitor log - should see immediate delivery, no queueing
```

### Scenario 2: Typing at CLI Prompt
**Setup:** Agent at `❯` prompt, actively typing
**Expected:** Mail notification queues
**Test:**
```bash
# Start typing at prompt (don't press Enter)
# In another terminal: send test mail
$PROJECT_ROOT/scripts/agent-mail-helper.sh send OrangeLantern "Test: Typing at prompt"
# Check monitor log - should see "Pane busy - queueing message"
```

### Scenario 3: Active Conversation (THE BUG FIX)
**Setup:** Agent in active conversation with Claude (prompt scrolled up)
**Expected:** Mail notification queues (THIS WAS BROKEN BEFORE)
**Test:**
```bash
# Start a conversation in Claude Code, let prompt scroll up
# While conversation active, send test mail from another terminal
$PROJECT_ROOT/scripts/agent-mail-helper.sh send OrangeLantern "Test: Active conversation"
# Check monitor log - should see "Pane busy - queueing message"
```

### Scenario 4: Claude Streaming Response
**Setup:** Claude generating a long response (streaming output)
**Expected:** Mail notification queues
**Test:**
```bash
# Ask Claude a question that generates long response
# While response streaming, send test mail from another terminal
$PROJECT_ROOT/scripts/agent-mail-helper.sh send OrangeLantern "Test: Streaming response"
# Check monitor log - should see "Pane busy - queueing message"
```

### Scenario 5: Copy Mode
**Setup:** User in tmux copy-mode (scrollback)
**Expected:** Mail notification queues
**Test:**
```bash
# Press Ctrl+b [ to enter copy-mode
# Send test mail from another terminal
$PROJECT_ROOT/scripts/agent-mail-helper.sh send OrangeLantern "Test: Copy mode"
# Check monitor log - should see "Pane busy - queueing message"
```

### Scenario 6: Queue Flush on Idle
**Setup:** Messages in queue, pane becomes idle
**Expected:** Queue flushes within 5 seconds (poll interval)
**Test:**
```bash
# Create queued messages (from scenarios above)
# Stop typing / exit conversation / exit copy-mode
# Wait up to 5 seconds
# Check monitor log - should see "Pane idle - flushing queue"
```

### Scenario 7: Inactive Pane (if MAIL_REQUIRE_PANE_ACTIVE=1)
**Setup:** Switch to different tmux pane/window
**Expected:** Mail notification delivers immediately (pane not active)
**Test:**
```bash
# Switch to different pane (Ctrl+b o)
# Send test mail from another terminal
$PROJECT_ROOT/scripts/agent-mail-helper.sh send OrangeLantern "Test: Inactive pane"
# Check monitor log - should see immediate delivery
```

## Key Metrics to Check

### In Monitor Log
- `Pane busy - queueing message` - When activity detected
- `Pane idle - flushing queue` - When queue flushes
- `Queue waiting (pane busy)...` - When queue waits
- No "interrupting mid-conversation" reports

### Using Debug Commands
```bash
# Check pane activity age
tmux display-message -t "$PANE" -p '#{pane_last_activity}'
date +%s
# Calculate: now - last_activity (should be < 12 for "busy")

# Check if in copy mode
tmux display-message -t "$PANE" -p '#{pane_in_mode}'
# Should be "1" in copy-mode, "0" otherwise

# Check if pane is active
tmux display-message -t "$PANE" -p '#{pane_active}'
# Should be "1" if active, "0" otherwise
```

## Success Criteria (from Bead Description)

- ✅ Mail notifications queue when user is in active conversation
- ✅ Mail notifications queue when user is typing at CLI prompt
- ✅ Queued messages flush when terminal becomes idle
- ✅ No false positives (don't queue when truly idle)
- ✅ Works across all tmux pane states

## Regression Tests

Ensure existing functionality still works:
- Autocomplete suggestions still filtered out (not treated as typing)
- Monitor continues running after errors (fault tolerance)
- Pane resolution still works
- Multiple agents can have separate monitors

## Performance Check

Monitor should remain responsive:
- Each poll cycle < 1 second
- Function execution < 100ms
- No memory leaks over 24 hours

## Edge Cases (from ChatGPT Analysis)

1. **Chatty background command** (e.g., `tail -f`)
   - With `MAIL_REQUIRE_PANE_ACTIVE=1`, only affects active pane
   - Consider if this is desired behavior

2. **Very long user pause** (> 12s while typing)
   - Increase `MAIL_BUSY_WINDOW_SEC` if needed
   - Prompt-based detection provides extra safety

3. **Clock skew**
   - Code includes safety: `if [ "$age" -lt 0 ]; then age=0; fi`

## Configuration Tuning

If false positives/negatives occur, adjust:

```bash
# Increase busy window for slower typists
export MAIL_BUSY_WINDOW_SEC=20

# Disable active-pane requirement (queue for all panes)
export MAIL_REQUIRE_PANE_ACTIVE=0
```

## Files Modified

- `scripts/monitor-agent-mail-to-terminal.sh`
  - Added configuration variables (lines ~38-39)
  - Added `is_pane_busy_for_notifications()` function (lines ~226-273)
  - Updated `send_to_terminal()` to use new function
  - Updated queue flush logic to use new function
