#!/bin/bash
# bv-open: Sync beads data and open BV interactive viewer in new iTerm window
#
# Usage: bv-open [bv options...]
#
# Examples:
#   bv-open              # Open interactive TUI
#   bv-open -label api   # Open filtered by label

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Build the bv command with any passed arguments
BV_ARGS="$*"

# Sync beads data first
echo "🔄 Syncing beads data..."
br sync --flush-only --force 2>/dev/null || {
    echo "Warning: Could not sync beads data."
}
echo "✅ Sync complete"

# Check if iTerm2 is available
if [ -d "/Applications/iTerm.app" ]; then
    echo "📺 Opening BV in new iTerm window..."
    osascript <<EOF
tell application "iTerm"
    activate
    if (count of windows) = 0 then
        set newWindow to (create window with default profile)
        tell current session of newWindow
            write text "cd '$PROJECT_DIR' && bv $BV_ARGS"
        end tell
    else
        tell current window
            set newTab to (create tab with default profile)
            tell current session of newTab
                write text "cd '$PROJECT_DIR' && bv $BV_ARGS"
            end tell
        end tell
    end if
end tell
EOF
else
    # Fallback: open in current terminal
    echo "Opening BV in current terminal..."
    cd "$PROJECT_DIR"
    exec bv $BV_ARGS
fi
