#!/usr/bin/env bash
# wake-agents.sh - Wake idle agent-runners and notify active agents
#
# Touches the wake trigger file so idle agent-runners check for beads
# immediately. Optionally broadcasts a mail notification to active agents.
#
# Usage:
#   ./scripts/wake-agents.sh                          # Just wake idle runners
#   ./scripts/wake-agents.sh --notify "New beads"     # Wake + broadcast message
#   ./scripts/wake-agents.sh --notify "New beads" --bead bd-xxx  # Include bead ID

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAKE_TRIGGER="/tmp/agent-runner-wake.trigger"

NOTIFY_MSG=""
BEAD_ID=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --notify)
            NOTIFY_MSG="$2"
            shift 2
            ;;
        --bead)
            BEAD_ID="$2"
            shift 2
            ;;
        -h|--help)
            sed -n '2,/^$/s/^# //p' "$0"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# 1. Touch trigger file to wake idle agent-runners
touch "$WAKE_TRIGGER"
echo "Touched wake trigger: $WAKE_TRIGGER"

# 2. Broadcast to active agents if message provided
if [ -n "$NOTIFY_MSG" ]; then
    subject="New work available"
    [ -n "$BEAD_ID" ] && subject="[$BEAD_ID] $subject"

    if [ -x "$SCRIPT_DIR/broadcast-to-swarm.sh" ]; then
        "$SCRIPT_DIR/broadcast-to-swarm.sh" @active "$subject" "$NOTIFY_MSG" \
            --type FYI --mail-only 2>/dev/null || true
        echo "Broadcast sent to @active agents"
    fi
fi
