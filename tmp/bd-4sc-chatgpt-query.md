# Mail Monitor Input Detection - Need Better Solution

## Current Problem

I have a mail monitor script that sends notifications to a tmux pane where an agent (Claude Code CLI) is running. The monitor has an `has_pending_input()` function to detect when the user is typing, so it can queue notifications instead of interrupting.

**What works**: Detects typing at the CLI prompt (`❯`) - notifications queue correctly
**What's broken**: Doesn't detect when user is in an active conversation - notifications interrupt

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
        return 1  # No prompt visible — claude is working
    fi

    # Check if text follows the prompt
    local after_prompt
    after_prompt=$(echo "$prompt_line" | sed 's/^[[:space:]]*❯//')

    # Check for autocomplete (dim/grey escape sequences)
    if echo "$after_prompt" | grep -qE $'\x1b\\[2m|\x1b\\[90m|\x1b\\[38;5;24[0-9]m'; then
        return 1  # It's autocomplete, not real typing
    fi

    # Check for non-whitespace after prompt
    local trimmed
    trimmed=$(echo "$after_prompt" | sed $'s/[\t \xc2\xa0]//g' | sed 's/\x1b\[[0-9;]*m//g')
    if [ -n "$trimmed" ]; then
        return 0  # User is typing on the prompt line
    fi

    return 1  # No pending input
}
```

## The Problem

During an active conversation with Claude:
- The `❯` prompt scrolls off-screen (not in the last 10 lines)
- The user might be reading Claude's response or typing a follow-up
- The function returns false (no pending input detected)
- Notifications interrupt the conversation

## What I Need to Detect

The function should return true (pending input) in these cases:
1. User is typing at the CLI prompt `❯` (already works)
2. User is in an active conversation (Claude is responding)
3. User is typing a message during a conversation
4. User is reading Claude's response (recent activity)

The function should return false (clear to notify) when:
- User is idle at an empty prompt
- Terminal has been inactive for a reasonable time
- No conversation is in progress

## Available Tools

- tmux commands for pane inspection
- tmux variables like `#{pane_in_mode}`, `#{pane_active}`, etc.
- Shell commands to analyze pane content
- Access to pane history, cursor position, etc.

## Possible Approaches to Evaluate

1. **Check tmux pane mode and cursor activity** - detect copy mode vs normal mode
2. **Monitor pane content change rate** - active conversation = frequent updates
3. **Check for thinking/response markers** - look for Claude's response patterns
4. **Use tmux's #{pane_in_mode} variable** - detect special modes
5. **Track time since last activity** - use tmux history timestamps
6. **Look for conversation markers** - detect if we're past the initial prompt state
7. **Cursor position analysis** - detect if cursor is in input area

## Requirements

- Must work when Claude is generating responses (thinking blocks, function calls, etc.)
- Must work when user is typing in conversation
- Should maintain backward compatibility with CLI prompt detection
- No false positives (don't queue when truly idle)
- Should be reasonably simple and reliable

## Question

**What's the best approach to detect "active conversation or user typing" in a tmux pane running Claude Code CLI?**

Please provide:
1. Your recommended approach and why
2. Specific tmux commands or checks to implement
3. Sample bash code if possible
4. How to handle edge cases (Claude still generating, user idle during conversation, etc.)

The solution should be defensive and prefer queueing (when uncertain) over interrupting.
