#!/usr/bin/env bash
# CM - CASS Memory System wrapper
# Gives agents persistent cross-session memory.
# Usage: ./scripts/cm.sh context "implement auth rate limiting"
#        ./scripts/cm.sh quickstart --json
#        ./scripts/cm.sh onboard status --json

set -uo pipefail

if command -v cm &>/dev/null; then
    exec cm "$@"
fi

# Common install locations
for candidate in "$HOME/.local/bin/cm" "/opt/homebrew/bin/cm" "/usr/local/bin/cm"; do
    if [ -x "$candidate" ]; then
        exec "$candidate" "$@"
    fi
done

echo "❌ cm not found. Install it:" >&2
echo "   brew install dicklesworthstone/tap/cm" >&2
echo "   or: curl -fsSL 'https://raw.githubusercontent.com/Dicklesworthstone/cass_memory_system/main/install.sh' | bash" >&2
exit 2
