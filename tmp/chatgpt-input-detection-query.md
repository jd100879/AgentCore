# Fix Mail Monitor Input Detection During Active Conversations

## Problem Statement

We have a tmux-based mail notification system for Claude Code agents. The current `has_pending_input()` function only detects typing at the CLI prompt (`❯`), NOT during active conversations. This causes mail notifications to interrupt users mid-conversation instead of queueing.

## Current Implementation

```bash
has_pending_input() {
    # Capture the last 10 lines of the pane
    local bottom
    bottom=$(tmux capture-pane -t "$MY_PANE" -p -e 2>/dev/null | tail -10)

    # Look for the Claude Code input prompt: ❯ at line start
    local prompt_line
    prompt_line=$(echo "$bottom" | grep '^[[:space:]]*❯' | tail -1)
    if [ -z "$prompt_line" ]; then
        return 1  # No prompt visible
    fi

    # Check for non-whitespace after prompt (with autocomplete filtering)
    local after_prompt
    after_prompt=$(echo "$prompt_line" | sed 's/^[[:space:]]*❯//')

    # Filter out dim/grey autocomplete suggestions
    if echo "$after_prompt" | grep -qE $'\x1b\\[2m|\x1b\\[90m|\x1b\\[38;5;24[0-9]m'; then
        return 1  # It's autocomplete suggestion
    fi

    # Check for actual typed content
    local trimmed
    trimmed=$(echo "$after_prompt" | sed $'s/[\t \xc2\xa0]//g' | sed 's/\x1b\[[0-9;]*m//g')
    if [ -n "$trimmed" ]; then
        return 0  # User is typing
    fi

    return 1  # No pending input
}
```

## Current Behavior

- ✅ Works: User typing at CLI prompt `❯` → notification queues
- ❌ Broken: User in active conversation → notification interrupts immediately

## Why It Breaks

During active conversations, the `❯` prompt scrolls off-screen (not in last 10 lines), so the function returns false even when the user is actively typing or Claude is generating a response.

## Requirements for Better Solution

Design a mechanism that:

1. **Detects active conversation state** (not just CLI prompt)
2. **Works when Claude is generating responses** (user waiting for response)
3. **Works when user is typing in conversation** (composing question/response)
4. **Maintains backward compatibility** with CLI prompt detection
5. **Doesn't rely on prompt being visible** in last N lines
6. **Avoids false positives** (don't queue when truly idle)

## Possible Approaches to Evaluate

Please evaluate these approaches and recommend the best solution:

### Approach 1: Tmux Pane Mode Detection
```bash
# Check if pane is in copy mode or has active input
tmux display-message -t "$MY_PANE" -p '#{pane_in_mode}'
```

### Approach 2: Content Change Rate Monitoring
```bash
# Capture pane, wait 1s, capture again, compare
# If changing → active conversation
before=$(tmux capture-pane -t "$MY_PANE" -p)
sleep 1
after=$(tmux capture-pane -t "$MY_PANE" -p)
if [ "$before" != "$after" ]; then
    # Active conversation
fi
```

### Approach 3: Response Markers Detection
```bash
# Check if last visible lines contain Claude's thinking/response markers
# Look for patterns like:
# - "thinking..." blocks
# - Streaming text (frequent updates)
# - Tool execution output
```

### Approach 4: Cursor Activity Detection
```bash
# Check tmux cursor position changes
tmux display-message -t "$MY_PANE" -p '#{cursor_x} #{cursor_y}'
```

### Approach 5: Pane Activity Timestamp
```bash
# Check last activity time
tmux display-message -t "$MY_PANE" -p '#{pane_last_activity}'
# Compare with current time to detect recent activity
```

## Additional Context

- **Environment**: macOS, tmux, Claude Code CLI
- **Frequency**: Function called every 5 seconds in monitor loop
- **Performance**: Should be fast (< 100ms) to not block monitoring
- **Reliability**: Must work 99%+ of the time (critical for agent workflow)

## What I Need From You

1. **Evaluate each approach** - pros, cons, reliability, edge cases
2. **Recommend the best solution** - which approach or combination works best
3. **Provide implementation** - complete bash function with defensive checks
4. **Identify edge cases** - what could still go wrong
5. **Suggest testing strategy** - how to verify it works

## Success Criteria

- Mail notifications queue when user is in active conversation
- Mail notifications queue when user is typing at CLI prompt
- Queued messages flush when terminal becomes idle
- No false positives (don't queue when truly idle)
- Works across all tmux pane states
- Maintains existing autocomplete filtering logic

Please design the best solution for this problem. Consider tmux capabilities, bash scripting best practices, and production reliability.
