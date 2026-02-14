# NEW TOPIC: Design Better Input Detection for Tmux Mail Notifications

**This is a completely new question, unrelated to any previous discussion.**

## The Problem

I have a bash script that monitors tmux panes and sends mail notifications to Claude Code agents. The current implementation has a bug:

**Current behavior:**
- When user is typing at the CLI prompt `❯` → notification is queued ✅
- When user is in an active conversation with Claude → notification interrupts ❌

**Why it fails:**
The `has_pending_input()` function only looks for the `❯` prompt in the last 10 lines. During active conversations, this prompt scrolls up and isn't visible anymore, so the function incorrectly returns "no pending input."

## Current Implementation (Simplified)

```bash
has_pending_input() {
    # Get last 10 lines of the tmux pane
    bottom=$(tmux capture-pane -t "$MY_PANE" -p -e 2>/dev/null | tail -10)

    # Look for CLI prompt ❯
    prompt_line=$(echo "$bottom" | grep '^[[:space:]]*❯' | tail -1)
    if [ -z "$prompt_line" ]; then
        return 1  # No prompt visible
    fi

    # Check if user has typed something after the prompt
    # (with autocomplete filtering logic omitted for clarity)
    # ... returns 0 if typing detected, 1 otherwise
}
```

## What I Need

I need a better detection mechanism that returns "true" (input pending) when:

1. User is typing at the CLI prompt `❯`
2. User is in an active conversation (typing a question)
3. Claude is generating a response (user is waiting)

And returns "false" (no input) when:

4. Terminal is idle at the CLI prompt with no typing

## Constraints

- Must use tmux commands (tmux capture-pane, display-message, etc.)
- Should be fast (< 100ms) - called every 5 seconds
- Must be reliable (99%+ accuracy)
- Bash script environment

## Possible Tmux Features to Use

```bash
# Pane mode (copy mode, normal, etc.)
tmux display-message -t "$MY_PANE" -p '#{pane_in_mode}'

# Cursor position
tmux display-message -t "$MY_PANE" -p '#{cursor_x} #{cursor_y}'

# Last activity timestamp
tmux display-message -t "$MY_PANE" -p '#{pane_last_activity}'

# Pane content
tmux capture-pane -t "$MY_PANE" -p
```

## Question

**What's the best way to detect "active conversation" state in tmux?**

Please provide:
1. A recommended approach with explanation
2. Complete bash function implementation
3. Edge cases to consider

Keep the answer concise and focused on the technical solution.
