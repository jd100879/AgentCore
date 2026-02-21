#!/usr/bin/env bash
# CASS - Coding Agent Session Search wrapper
# Search across all past agent sessions for solutions and patterns.
# Usage: ./scripts/cass.sh search "authentication error" --robot --limit 5
#        ./scripts/cass.sh health --json
#        ./scripts/cass.sh index --full

set -uo pipefail

if command -v cass &>/dev/null; then
    exec cass "$@"
fi

for candidate in "$HOME/.local/bin/cass" "/opt/homebrew/bin/cass" "/usr/local/bin/cass"; do
    if [ -x "$candidate" ]; then
        exec "$candidate" "$@"
    fi
done

echo "❌ cass not found. Install it:" >&2
echo "   brew install dicklesworthstone/tap/cass" >&2
echo "   or: curl -fsSL 'https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_session_search/main/install.sh' | bash" >&2
exit 2
