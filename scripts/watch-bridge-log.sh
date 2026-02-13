#!/usr/bin/env bash
# Watch for bridge log file and tail it when it appears

LOG_FILE="tmp/bridge.log"
cd "$(dirname "$0")/.." || exit 1

echo "Watching for bridge log at: $LOG_FILE"
echo "Waiting for bridge to start..."
echo ""

# Wait for log file to be created
while [ ! -f "$LOG_FILE" ]; do
  sleep 1
done

echo "Bridge log detected! Monitoring output..."
echo "═══════════════════════════════════════"
echo ""

# Tail the log file
tail -f "$LOG_FILE"
