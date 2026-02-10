#!/bin/bash
# Agent Session Validation Script
# Tests that agent registration and mail monitoring are working correctly
# Usage: ./scripts/validate-agent-session.sh [--verbose] [pane_id] [expected_agent_name]

# Note: set -e intentionally omitted to allow script to continue through test failures

# Source shared project configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/project-config.sh"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Flags
VERBOSE=false

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Helper functions
pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

info() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}ℹ${NC} $1"
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        *)
            break
            ;;
    esac
done

# Get pane ID (from parameter or detect current)
if [ -n "$1" ]; then
    PANE_ID="$1"
    shift
else
    PANE_ID=$(tmux display-message -p "#{session_name}:#{window_index}.#{pane_index}" 2>/dev/null || echo "")
    if [ -z "$PANE_ID" ]; then
        echo -e "${RED}Error: Not running in tmux and no pane ID provided${NC}"
        echo "Usage: $0 [--verbose] [pane_id] [expected_agent_name]"
        exit 1
    fi
fi

EXPECTED_AGENT="$1"

SAFE_PANE=$(echo "$PANE_ID" | tr ':.' '-')

echo "=========================================="
if [ "$VERBOSE" = true ]; then
    echo "Agent Session Validation (VERBOSE MODE)"
else
    echo "Agent Session Validation"
fi
echo "=========================================="
echo "Pane: $PANE_ID (${SAFE_PANE})"
if [ "$VERBOSE" = true ]; then
    echo "Mode: Verbose (includes log analysis)"
fi
echo ""

# Test 1: Check agent-name file exists
echo "Test 1: Agent Name File"
AGENT_NAME_FILE="$PIDS_DIR/${SAFE_PANE}.agent-name"
if [ -f "$AGENT_NAME_FILE" ]; then
    AGENT_NAME=$(cat "$AGENT_NAME_FILE")
    pass "Agent name file exists: $AGENT_NAME_FILE"
    pass "Agent name: $AGENT_NAME"

    # Check if it matches expected
    if [ -n "$EXPECTED_AGENT" ] && [ "$AGENT_NAME" != "$EXPECTED_AGENT" ]; then
        fail "Agent name mismatch: expected '$EXPECTED_AGENT', got '$AGENT_NAME'"
    fi
else
    fail "Agent name file missing: $AGENT_NAME_FILE"
    AGENT_NAME=""
fi
echo ""

# Test 2: Check identity file exists and matches
echo "Test 2: Identity File"
IDENTITY_FILE="$PANES_DIR/${SAFE_PANE}.identity"
if [ -f "$IDENTITY_FILE" ]; then
    pass "Identity file exists: $IDENTITY_FILE"

    # Check if it's valid JSON
    if jq empty "$IDENTITY_FILE" 2>/dev/null; then
        pass "Identity file is valid JSON"

        # Check pane field
        IDENTITY_PANE=$(jq -r '.pane // empty' "$IDENTITY_FILE")
        if [ "$IDENTITY_PANE" = "$PANE_ID" ]; then
            pass "Pane ID matches: $PANE_ID"
        else
            fail "Pane ID mismatch: expected '$PANE_ID', got '$IDENTITY_PANE'"
        fi

        # Check agent_mail_name field
        IDENTITY_AGENT=$(jq -r '.agent_mail_name // empty' "$IDENTITY_FILE")
        if [ -n "$IDENTITY_AGENT" ]; then
            pass "Agent mail name set: $IDENTITY_AGENT"

            # Check if it matches agent-name file
            if [ -n "$AGENT_NAME" ] && [ "$IDENTITY_AGENT" != "$AGENT_NAME" ]; then
                fail "Agent name mismatch between files: agent-name='$AGENT_NAME', identity='$IDENTITY_AGENT'"
            fi
        else
            fail "Agent mail name not set in identity file"
        fi
    else
        fail "Identity file is not valid JSON"
    fi
else
    warn "Identity file missing: $IDENTITY_FILE (may not be required)"
fi
echo ""

# Test 3: Check if agent is registered in mail system
echo "Test 3: Mail System Registration"
if [ -n "$AGENT_NAME" ]; then
    if "$SCRIPT_DIR/agent-mail-helper.sh" list | grep -q "^$AGENT_NAME"; then
        pass "Agent registered in mail system: $AGENT_NAME"
    else
        fail "Agent not found in mail system: $AGENT_NAME"
    fi
else
    fail "Cannot check mail registration - no agent name"
fi
echo ""

# Test 4: Check mail monitor status
echo "Test 4: Mail Monitor"
PID_FILE="$PIDS_DIR/${SAFE_PANE}.mail-monitor.pid"
if [ -f "$PID_FILE" ]; then
    MONITOR_PID=$(cat "$PID_FILE")
    if ps -p "$MONITOR_PID" > /dev/null 2>&1; then
        pass "Mail monitor is running (PID: $MONITOR_PID)"

        # Check if it's monitoring the correct agent
        if ps -p "$MONITOR_PID" -o args= | grep -q "$AGENT_NAME"; then
            pass "Monitor is tracking correct agent: $AGENT_NAME"
        else
            ACTUAL_AGENT=$(ps -p "$MONITOR_PID" -o args= | grep -oE '[A-Z][a-z]+[A-Z][a-z]+' | tail -1)
            fail "Monitor tracking wrong agent: expected '$AGENT_NAME', got '$ACTUAL_AGENT'"
        fi

        # Verbose: Parse monitor logs for retry patterns
        if [ "$VERBOSE" = true ]; then
            LOG_FILE="$LOGS_DIR/${SAFE_PANE}.mail-monitor.log"
            if [ -f "$LOG_FILE" ]; then
                info "Analyzing monitor logs..."

                # Check for retry attempts
                if grep -q "Attempt [0-9]*/[0-9]*" "$LOG_FILE" 2>/dev/null; then
                    RETRY_COUNT=$(grep -c "Attempt [0-9]*/[0-9]*" "$LOG_FILE")
                    info "Found $RETRY_COUNT retry attempt(s) in log"

                    # Show retry messages
                    grep "Attempt [0-9]*/[0-9]*" "$LOG_FILE" | tail -5 | while read -r line; do
                        info "  $line"
                    done
                else
                    info "No retry attempts found (clean startup)"
                fi

                # Check for success messages
                if grep -q "Monitor started" "$LOG_FILE" 2>/dev/null; then
                    info "Monitor startup confirmed in logs"
                fi

                # Check for validation success
                if grep -q "Validation succeeded" "$LOG_FILE" 2>/dev/null; then
                    ATTEMPT=$(grep "Validation succeeded" "$LOG_FILE" | tail -1 | grep -oE "attempt [0-9]+" | grep -oE "[0-9]+")
                    if [ -n "$ATTEMPT" ]; then
                        info "Validation succeeded on attempt $ATTEMPT"
                    fi
                fi
            else
                warn "Monitor log file not found: $LOG_FILE"
            fi
        fi
    else
        fail "Mail monitor not running (stale PID file)"
    fi
else
    fail "Mail monitor PID file missing: $PID_FILE"
fi
echo ""

# Test 5: Check last message tracking
echo "Test 5: Message Tracking"
if [ -n "$AGENT_NAME" ]; then
    LAST_MSG_FILE="$PIDS_DIR/$(echo $AGENT_NAME | tr 'A-Z' 'a-z').last-msg-id"
    if [ -f "$LAST_MSG_FILE" ]; then
        LAST_MSG_ID=$(cat "$LAST_MSG_FILE")
        pass "Last message tracking file exists: $LAST_MSG_ID"
    else
        warn "Last message tracking file missing (will be created on first check)"
    fi
else
    fail "Cannot check message tracking - no agent name"
fi
echo ""

# Summary
echo "=========================================="
echo "Validation Summary"
echo "=========================================="
echo -e "${GREEN}Passed:${NC} $PASSED"
echo -e "${RED}Failed:${NC} $FAILED"
echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All critical tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Validation failed with $FAILED error(s)${NC}"
    exit 1
fi
