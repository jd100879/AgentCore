#!/usr/bin/env bash
# next-bead.sh - Trigger agent restart after bead completion
#
# Called by post-bead-close hook after br close.
# Sends /exit to the agent's tmux pane so claude exits cleanly.
# agent-runner.sh then loops back, claims the next bead, and
# launches claude with fresh context.
#
# Part of: Autonomous Agent Lifecycle System (bd-3u96)

set -uo pipefail

# Lock file prevents double-trigger (hook + agent both calling this)
LOCK_FILE="/tmp/next-bead-${TMUX_PANE:-$$}.lock"
if [ -f "$LOCK_FILE" ]; then
    lock_age=$(( $(date +%s) - $(stat -f %m "$LOCK_FILE" 2>/dev/null || echo 0) ))
    if [ "$lock_age" -gt 240 ]; then
        echo "Cleaning stale lock (age: ${lock_age}s)"
        rm -f "$LOCK_FILE"
    elif [ "$lock_age" -lt 120 ]; then
        echo "Transition already in progress (lock age: ${lock_age}s). Skipping."
        exit 0
    fi
fi
touch "$LOCK_FILE"
trap "rm -f '$LOCK_FILE'" EXIT

# Check .no-exit flag — if set, stay in session (REPL loop mode)
PROJECT_ROOT="${PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
NO_EXIT_FILE="$PROJECT_ROOT/.no-exit"
if [ -f "$NO_EXIT_FILE" ] && grep -q "on" "$NO_EXIT_FILE" 2>/dev/null; then
    echo "(.no-exit is on — staying in session)"
    exit 0
fi

# Send /exit to the agent's tmux pane to trigger clean restart via agent-runner
pane="${TMUX_PANE:-}"
if [ -n "$pane" ]; then
    echo "Sending /exit to pane $pane (agent-runner will claim next bead on restart)"
    sleep 2
    tmux send-keys -t "$pane" "/exit" Enter
else
    echo "No TMUX_PANE — cannot send /exit automatically"
fi

exit 0
