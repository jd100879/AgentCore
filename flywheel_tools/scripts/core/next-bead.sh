#!/usr/bin/env bash
# next-bead.sh - Transition to next bead with context clear
#
# Called by claude (via Bash tool) after closing a bead.
# Claims the next bead, then sends /clear + new prompt to the tmux pane
# so claude starts the next bead with fresh context.
#
# Usage (from within claude):
#   ./scripts/next-bead.sh
#
# Part of: Autonomous Agent Lifecycle System (bd-3u96)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Lock file prevents double-trigger (hook + agent both calling this)
LOCK_FILE="/tmp/next-bead-${TMUX_PANE:-$$}.lock"
if [ -f "$LOCK_FILE" ]; then
    lock_age=$(( $(date +%s) - $(stat -f %m "$LOCK_FILE" 2>/dev/null || echo 0) ))
    # Auto-cleanup stale locks (max runtime + buffer = 240s)
    if [ "$lock_age" -gt 240 ]; then
        echo "Cleaning stale lock (age: ${lock_age}s)"
        rm -f "$LOCK_FILE"
    elif [ "$lock_age" -lt 120 ]; then
        echo "Transition already in progress (lock age: ${lock_age}s). Skipping."
        exit 0
    fi
fi
touch "$LOCK_FILE"

# Set trap in foreground to ensure cleanup on ANY exit path
# This is belt-and-suspenders with the background process trap
trap "rm -f '$LOCK_FILE'" EXIT

# Get agent identity for tracking file
AGENT_NAME=$("$SCRIPT_DIR/agent-mail-helper.sh" whoami 2>/dev/null || echo "unknown")

# Claim next bead
br sync --flush-only --force >/dev/null 2>&1 || true

bv_output=$(bv --robot-next --format json 2>/dev/null || echo "{}")
bead_id=$(echo "$bv_output" | jq -r '.id // empty' 2>/dev/null)

prompt=""

if [ -z "$bead_id" ] || [ "$bead_id" = "null" ]; then
    echo "No beads available. Clearing context anyway."
    # Clear stale tracking file so enforcement doesn't think we still have a bead
    rm -f "/tmp/agent-bead-${AGENT_NAME}.txt"
    prompt="No beads are available right now. Check your inbox for work: \$PROJECT_ROOT/scripts/agent-mail-helper.sh inbox"
else
    bead_title=$(echo "$bv_output" | jq -r '.title // "untitled"' 2>/dev/null)

    # Claim it
    claim_output=$(br update "$bead_id" --status in_progress --owner "$AGENT_NAME" --assignee "$AGENT_NAME" 2>&1)
    claim_status=$?
    if [ $claim_status -ne 0 ]; then
        echo "⚠️  Warning: Failed to claim bead $bead_id (br update failed)" >&2
        echo "$claim_output" >&2
        echo "   Continuing anyway - check assignee manually if needed" >&2
    fi

    # Verify the claim succeeded
    verify_assignee=$(br show "$bead_id" --json 2>/dev/null | jq -r '.[0].assignee // empty' 2>/dev/null)
    if [ "$verify_assignee" != "$AGENT_NAME" ]; then
        echo "❌ ERROR: Failed to claim bead $bead_id" >&2
        echo "   Expected assignee: $AGENT_NAME" >&2
        echo "   Actual assignee: ${verify_assignee:-<none>}" >&2
        echo "   Another agent may have claimed it first." >&2
        echo "   Clearing stale tracking file..." >&2
        rm -f "/tmp/agent-bead-${AGENT_NAME}.txt"
        rm -f "$LOCK_FILE"
        exit 1
    fi

    # Update tracking file (only if claim verified)
    echo "$bead_id" > "/tmp/agent-bead-${AGENT_NAME}.txt"

    # Get bead details for the prompt
    bead_json=$(br show "$bead_id" --json 2>/dev/null || echo "[]")
    description=$(echo "$bead_json" | jq -r '.[0].description // ""' 2>/dev/null)
    priority=$(echo "$bead_json" | jq -r '.[0].priority // ""' 2>/dev/null)

    prompt="Work on bead $bead_id: $bead_title."
    [ -n "$description" ] && prompt="$prompt Description: $description"
    [ -n "$priority" ] && prompt="$prompt Priority: $priority"
    prompt="$prompt Check inbox first, then complete this task."

    echo "Claimed bead $bead_id: $bead_title"
fi


# Just report the claimed bead - no automatic /clear
if [ -n "$bead_id" ]; then
    echo ""
    echo "✓ Claimed next bead: $bead_id"
    echo "  $prompt"
    echo ""
    echo "Work on this bead now. No automatic /clear - context preserved."
else
    echo ""
    echo "No beads available. Check your inbox for work."
fi

exit 0
