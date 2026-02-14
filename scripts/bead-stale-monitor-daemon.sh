#!/bin/bash
# [bd-14fh] Foreground daemon wrapper for launchd
# Runs bead-stale-monitor checks in a foreground loop (for launchd supervision)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MONITOR_SCRIPT="$PROJECT_ROOT/flywheel_tools/scripts/beads/bead-stale-monitor.sh"

# Configuration
CHECK_INTERVAL="${1:-60}"  # Check every 60 seconds by default

echo "[$(date)] Bead stale monitor daemon started (launchd mode)"
echo "Check interval: ${CHECK_INTERVAL}s"
echo "Monitor script: $MONITOR_SCRIPT"
echo ""

# Run checks in foreground loop (launchd will supervise this process)
while true; do
    # Run a single check
    "$MONITOR_SCRIPT" check 2>&1 || echo "Check failed, continuing..."

    # Wait before next check
    sleep "$CHECK_INTERVAL"
done
