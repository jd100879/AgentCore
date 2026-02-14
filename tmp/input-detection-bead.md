# Fix Mail Monitor Input Detection During Active Conversations

## Problem
Mail monitor's `has_pending_input()` function only detects typing at the Claude CLI prompt (`❯`), NOT during active conversations. This causes mail notifications to interrupt users mid-conversation instead of queueing.

## Current Behavior
- ✅ Works: User typing at CLI prompt `❯` → notification queues
- ❌ Broken: User in active conversation → notification interrupts

## Root Cause
`has_pending_input()` looks for the `❯` prompt in the last 10 lines of the pane:
```bash
bottom=$(tmux capture-pane -t "$MY_PANE" -p -e 2>/dev/null | tail -10)
prompt_line=$(echo "$bottom" | grep '^[[:space:]]*❯' | tail -1)
```

During conversations, the `❯` prompt scrolls off-screen, so the function returns false even when the user is actively typing.

## Context
- File: `scripts/monitor-agent-mail-to-terminal.sh`
- Function: `has_pending_input()` (lines 180-220)
- This WAS working properly before (user confirmed)
- Recent change (bd-dhv) added autocomplete detection but didn't break core logic
- Issue affects all agents across all projects

## Evidence
Tested 2026-02-13 20:19:
- Sent test message while TopazDeer in active conversation
- Notification interrupted immediately (not queued)
- Debug log shows: "[DEBUG] Sending line: 📨 NEW MAIL from TopazDeer"
- No "[Pending input detected - queueing message]" log entry

## What Needs to Happen
Ask ChatGPT to design a better input detection mechanism that:
1. Detects active conversation state (not just CLI prompt)
2. Works when Claude is generating responses
3. Works when user is typing in conversation
4. Maintains backward compatibility with CLI prompt detection
5. Doesn't rely on prompt being visible in last N lines

## Possible Approaches (for ChatGPT to evaluate)
1. Check tmux pane mode (copy mode vs normal) and cursor activity
2. Monitor pane content change rate (active = changing frequently)
3. Check if last line contains thinking/response markers
4. Use tmux's #{pane_in_mode} variable
5. Track time since last user input via tmux history

## Acceptance Criteria
- Mail notifications queue when user is in active conversation
- Mail notifications queue when user is typing at CLI prompt
- Queued messages flush when terminal becomes idle
- No false positives (don't queue when truly idle)
- Works across all tmux pane states

## Files to Modify
- scripts/monitor-agent-mail-to-terminal.sh (has_pending_input function)

## Verification
- Send test mail while agent in active conversation → queues
- Send test mail while agent at CLI prompt typing → queues  
- Send test mail while agent idle at prompt → delivers immediately
- Check queue file has entries when typing detected
- All existing integration tests still pass
