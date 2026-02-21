#!/usr/bin/env bash
# UBS - Ultimate Bug Scanner wrapper
# Locates and runs ubs, falling back to AgentCore installation if not in PATH.
# Usage: ./scripts/ubs.sh [ubs-args...]
#   ./scripts/ubs.sh --staged
#   ./scripts/ubs.sh $(git diff --name-only HEAD)
#   ./scripts/ubs.sh . --format=json

set -uo pipefail

# 1. Prefer system ubs (Homebrew / ~/.local/bin)
if command -v ubs &>/dev/null; then
    exec ubs "$@"
fi

# 2. Fall back to AgentCore installation
REAL_SCRIPT="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
AGENTCORE_ROOT="$(cd "$(dirname "$REAL_SCRIPT")/../../.." && pwd)"
UBS_BIN="$AGENTCORE_ROOT/ultimate_bug_scanner/ubs"

if [ -x "$UBS_BIN" ]; then
    exec "$UBS_BIN" "$@"
fi

echo "❌ ubs not found. Install it:" >&2
echo "   brew install dicklesworthstone/tap/ubs" >&2
echo "   or: curl -fsSL 'https://raw.githubusercontent.com/Dicklesworthstone/ultimate_bug_scanner/master/install.sh' | bash" >&2
exit 2
