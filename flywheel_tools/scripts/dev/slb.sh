#!/usr/bin/env bash
# SLB - Simultaneous Launch Button wrapper
# Two-person rule for destructive commands. Requires peer approval before execution.
# Usage: ./scripts/slb.sh submit "rm -rf dist/" --risk=high
#        ./scripts/slb.sh dashboard
#        ./scripts/slb.sh review <id> --approve

set -uo pipefail

if command -v slb &>/dev/null; then
    exec slb "$@"
fi

for candidate in "/opt/homebrew/bin/slb" "$HOME/.local/bin/slb" "/usr/local/bin/slb"; do
    if [ -x "$candidate" ]; then
        exec "$candidate" "$@"
    fi
done

echo "❌ slb not found. Install it:" >&2
echo "   brew install dicklesworthstone/tap/slb" >&2
exit 2
