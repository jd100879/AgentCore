#!/bin/bash
# bv-sync: Sync beads data to JSONL format for BV
#
# Usage: bv-sync [bv-command...]
#
# Examples:
#   bv-sync                     # Just sync data
#   bv-sync --robot-triage     # Sync then run BV command
#   bv-sync --robot-next       # Sync then get recommendation

set -euo pipefail

# Sync beads data to JSONL format for BV
echo "🔄 Syncing beads data to JSONL format..."
br sync --flush-only --force 2>/dev/null || {
    echo "Warning: Could not sync beads data. BV may show outdated information."
}

# If arguments provided, run BV with them
if [ $# -gt 0 ]; then
    echo "🤖 Running BV with arguments: $*"
    exec bv "$@"
else
    echo "✅ Sync complete. Use 'bv' command to access fresh data."
fi