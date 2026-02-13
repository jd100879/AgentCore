# Browser Worker Instructions for Claude Code

## Overview

The browser worker (`scripts/chatgpt/browser-worker.mjs`) is a long-running process that maintains ONE persistent browser window for all ChatGPT interactions. This avoids window spam and focus stealing.

## Architecture

```
[Claude Agent]
    ↓ writes
.flywheel/browser-request.json
    ↓ read by
[browser-worker.mjs] (background process)
    ↓ uses
[Chromium Browser] (persistent window)
    ↓ extracts response
.flywheel/browser-response.json
    ↑ read by
[send-to-worker.mjs]
    ↑ returns to
[Claude Agent]
```

## Check if Worker is Running

```bash
if [ -f .flywheel/browser-worker-pid.txt ]; then
  WORKER_PID=$(cat .flywheel/browser-worker-pid.txt)
  if kill -0 "$WORKER_PID" 2>/dev/null; then
    echo "Worker running: PID $WORKER_PID"
    # Worker is alive - proceed
  else
    echo "Worker not running (stale PID)"
    # Start worker
  fi
else
  echo "Worker not running (no PID file)"
  # Start worker
fi
```

## Start Worker

```bash
# Start browser worker in background
node scripts/chatgpt/browser-worker.mjs > .flywheel/browser-worker.log 2>&1 &
WORKER_PID=$!
echo $WORKER_PID > .flywheel/browser-worker-pid.txt

# Wait for ready signal (max 10 seconds)
for i in {1..20}; do
  if [ -f .flywheel/browser-ready.txt ]; then
    echo "Worker ready"
    break
  fi
  sleep 0.5
done

# Verify worker started
if [ ! -f .flywheel/browser-ready.txt ]; then
  echo "ERROR: Worker failed to start"
  tail -20 .flywheel/browser-worker.log
  exit 1
fi
```

## Send Message to Worker

```bash
# Use send-to-worker.mjs (NOT post-and-extract.mjs)
node scripts/chatgpt/send-to-worker.mjs \
  --message-file tmp/message.txt \
  --conversation-url "$(jq -r .crt_url .flywheel/chatgpt.json)" \
  --out tmp/response.json \
  --timeout 120000

# Check result
if [ $? -eq 0 ]; then
  echo "Message sent successfully"
  # Response is in tmp/response.json
else
  echo "ERROR: Message failed"
  # Check worker log: tail -20 .flywheel/browser-worker.log
fi
```

## Health Check

```bash
# Check if worker is responsive (has processed recent requests)
if [ -f .flywheel/browser-worker.log ]; then
  LAST_ACTIVITY=$(tail -1 .flywheel/browser-worker.log)
  echo "Last activity: $LAST_ACTIVITY"

  # If log shows errors or no recent activity, restart worker
  if grep -q "ERROR" <<< "$LAST_ACTIVITY"; then
    echo "Worker has errors - restarting"
    # Stop and restart worker
  fi
fi
```

## Stop Worker

```bash
if [ -f .flywheel/browser-worker-pid.txt ]; then
  WORKER_PID=$(cat .flywheel/browser-worker-pid.txt)
  if kill -0 "$WORKER_PID" 2>/dev/null; then
    kill -TERM "$WORKER_PID"
    echo "Worker stopped (PID: $WORKER_PID)"
  fi
  rm -f .flywheel/browser-worker-pid.txt .flywheel/browser-ready.txt
fi
```

## Restart Worker

```bash
# Stop existing worker
if [ -f .flywheel/browser-worker-pid.txt ]; then
  WORKER_PID=$(cat .flywheel/browser-worker-pid.txt)
  kill -TERM "$WORKER_PID" 2>/dev/null
  sleep 2
fi

# Clean up state files
rm -f .flywheel/browser-worker-pid.txt .flywheel/browser-ready.txt .flywheel/browser-request.json .flywheel/browser-response.json

# Start fresh worker
node scripts/chatgpt/browser-worker.mjs > .flywheel/browser-worker.log 2>&1 &
WORKER_PID=$!
echo $WORKER_PID > .flywheel/browser-worker-pid.txt

# Wait for ready
for i in {1..20}; do
  if [ -f .flywheel/browser-ready.txt ]; then
    echo "Worker restarted successfully"
    break
  fi
  sleep 0.5
done
```

## Files

- `.flywheel/browser-worker-pid.txt` - Worker process ID
- `.flywheel/browser-ready.txt` - Worker ready signal (timestamp)
- `.flywheel/browser-worker.log` - Worker stdout/stderr
- `.flywheel/browser-request.json` - Request queue (deleted after read)
- `.flywheel/browser-response.json` - Response from ChatGPT

## Expected Worker Behavior

**Normal operation log output:**
```
=== Browser Worker Starting ===
✓ Browser opened and hidden

Worker ready. Watching for requests at: .flywheel/browser-request.json
Press Ctrl+C to stop.

[2026-02-13T16:29:18.208Z] Processing request: https://chatgpt.com/c/...
✓ Response written (93 chars)
```

**Error indicators:**
- `ERROR:` in log
- `✗` symbols in log
- No `✓ Response written` after request
- Worker PID not responding to `kill -0`

## Integration with Orchestrator

When orchestrator needs to send ChatGPT messages:

1. Check if worker is running (see "Check if Worker is Running")
2. If not running, start it (see "Start Worker")
3. Send message using `send-to-worker.mjs` (see "Send Message to Worker")
4. If message fails, check worker health and restart if needed
5. On orchestrator shutdown, stop worker (see "Stop Worker")

## Critical Points

- ✅ Always use `send-to-worker.mjs`, NOT `post-and-extract.mjs`
- ✅ Worker must be running before sending messages
- ✅ One worker handles all ChatGPT interactions
- ✅ Worker reuses same browser window (no window spam)
- ✅ Browser window is visible but only opens once
- ❌ Do not start multiple workers (only one should run)
- ❌ Do not use Playwright MCP for ChatGPT (use worker instead)
