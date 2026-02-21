#!/usr/bin/env bash
# NTM - Named Tmux Manager wrapper
# Spawn and coordinate Claude/Codex/Gemini agent fleets across tmux sessions.
# Usage: ./scripts/ntm.sh --robot-status
#        ./scripts/ntm.sh --robot-list
#        ./scripts/ntm.sh --robot-send=myproject --message "Next task"

set -uo pipefail

if command -v ntm &>/dev/null; then
    exec ntm "$@"
fi

for candidate in "/opt/homebrew/bin/ntm" "$HOME/.local/bin/ntm" "/usr/local/bin/ntm"; do
    if [ -x "$candidate" ]; then
        exec "$candidate" "$@"
    fi
done

echo "❌ ntm not found. Install it:" >&2
echo "   curl -fsSL 'https://raw.githubusercontent.com/Dicklesworthstone/ntm/main/install.sh' | bash -s -- --easy-mode" >&2
exit 2
