#!/usr/bin/env bash
# BV - Beads Viewer wrapper
# Full TUI for beads: Kanban board, dependency graph, critical path, insights.
# Usage: ./scripts/bv.sh           # launch TUI
#        ./scripts/bv.sh --json    # machine-readable output

set -uo pipefail

if command -v bv &>/dev/null; then
    exec bv "$@"
fi

for candidate in "$HOME/.local/bin/bv" "/opt/homebrew/bin/bv" "/usr/local/bin/bv"; do
    if [ -x "$candidate" ]; then
        exec "$candidate" "$@"
    fi
done

echo "❌ bv not found. Install it:" >&2
echo "   brew install dicklesworthstone/tap/bv" >&2
exit 2
