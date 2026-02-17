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

# Check per-agent .no-exit flag (pids/{SAFE_PANE}.no-exit)
PROJECT_ROOT="${PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
pane="${TMUX_PANE:-}"

# Resolve SAFE_PANE for per-agent flag lookup
SAFE_PANE=""
if [ -n "$pane" ]; then
    PANE_ID=$(tmux display-message -t "$pane" -p "#{session_name}:#{window_index}.#{pane_index}" 2>/dev/null || echo "")
    [ -n "$PANE_ID" ] && SAFE_PANE=$(echo "$PANE_ID" | tr ':.' '-')
fi

if [ -n "$SAFE_PANE" ] && [ -f "$PROJECT_ROOT/pids/${SAFE_PANE}.no-exit" ]; then
    if grep -q "on" "$PROJECT_ROOT/pids/${SAFE_PANE}.no-exit" 2>/dev/null; then
        echo "(.no-exit is on — staying in session)"
        exit 0
    fi
fi

# Send /exit to the agent's tmux pane to trigger clean restart via agent-runner
if [ -n "$pane" ]; then
    echo "Sending /exit to pane $pane (agent-runner will claim next bead on restart)"
    sleep 2
    tmux send-keys -t "$pane" "/exit" Enter
    # Slash-command autocomplete may consume the first Enter (selecting the completion).
    # A second Enter after a short delay actually executes /exit.
    sleep 0.5
    tmux send-keys -t "$pane" "" Enter
else
    echo "No TMUX_PANE — cannot send /exit automatically"
fi

exit 0
