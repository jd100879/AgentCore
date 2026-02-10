#!/bin/bash
# Launcher script for multi-agent session creator
# This script can be double-clicked in Finder (if file association is set up)
# or run from terminal

# Detect the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if running in iTerm
if [[ "$TERM_PROGRAM" == "iTerm.app" ]]; then
    # Already in iTerm, just run the script
    bash "$SCRIPT_DIR/start-multi-agent-session.sh"
else
    # Try to open in iTerm
    if command -v osascript >/dev/null 2>&1; then
        osascript <<EOF
tell application "iTerm"
    activate
    tell current window
        create tab with default profile
        tell current session
            write text "bash '$SCRIPT_DIR/start-multi-agent-session.sh'"
        end tell
    end tell
end tell
EOF
    else
        # Fallback: just run in current terminal
        echo "Note: Running in current terminal (iTerm not available)"
        bash "$SCRIPT_DIR/start-multi-agent-session.sh"
    fi
fi
