#!/usr/bin/env bash
# Start bridge agent with output logged to tmp/bridge.log

cd "$(dirname "$0")/.." || exit 1

export AGENT_IDENTITY="ChatGPTBridge"
export BRIDGE_CHECK_INTERVAL=3

LOG_FILE="tmp/bridge.log"
mkdir -p tmp

echo "=== Bridge started at $(date) ===" | tee -a "$LOG_FILE"
echo "Logging to: $LOG_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Run bridge with output to both terminal and log file
bash scripts/chatgpt/bridge-agent-loop.sh 2>&1 | tee -a "$LOG_FILE"
