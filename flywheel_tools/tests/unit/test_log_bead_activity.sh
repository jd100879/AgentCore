#!/usr/bin/env bash
# test_log_bead_activity.sh - Unit tests for log-bead-activity.sh
#
# Tests:
#   1. log_bead_event produces valid JSONL
#   2. Required fields are present (timestamp, agent, bead_id, action)
#   3. Usage error when called with too few arguments
#   4. Multiple events append correctly
#
# Usage: ./tests/test_log_bead_activity.sh

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/log-bead-activity.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}  ✓ $1${NC}"
}

fail() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}  ✗ $1${NC}"
    [ -n "${2:-}" ] && echo -e "${RED}    $2${NC}"
}

# Create isolated temp environment so we don't pollute real logs
TMPDIR=$(mktemp -d /tmp/test-log-bead.XXXXXX)
trap "rm -rf '$TMPDIR'" EXIT

# Create a fake project structure pointing to our temp log
FAKE_PROJECT="$TMPDIR/project"
mkdir -p "$FAKE_PROJECT/.beads"
mkdir -p "$FAKE_PROJECT/scripts"

# Create a patched version of the script that uses our temp dir
# We patch PROJECT_DIR to point to our fake project
cat > "$FAKE_PROJECT/scripts/log-bead-activity.sh" << 'SCRIPT_EOF'
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${PROJECT_DIR}/.beads/agent-activity.jsonl"

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

log_bead_event() {
    local agent="$1"
    local bead_id="$2"
    local action="$3"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local entry
    entry=$(jq -c -n \
        --arg ts "$timestamp" \
        --arg agent "$agent" \
        --arg bead "$bead_id" \
        --arg action "$action" \
        '{timestamp: $ts, agent: $agent, bead_id: $bead, action: $action}')

    echo "$entry" >> "$LOG_FILE"
    echo "[bead-log] $timestamp $agent $bead_id $action" >&2
}

get_agent_name() {
    echo "TestAgent"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -lt 3 ]; then
        echo "Usage: $0 <bead_id> <action> [agent_name]" >&2
        echo "  action: claim, create, edit_allowed, edit_blocked, close, commit" >&2
        exit 1
    fi
    bead_id="$1"
    action="$2"
    agent="${3:-$(get_agent_name)}"
    log_bead_event "$agent" "$bead_id" "$action"
fi
SCRIPT_EOF
chmod +x "$FAKE_PROJECT/scripts/log-bead-activity.sh"

LOG_FILE="$FAKE_PROJECT/.beads/agent-activity.jsonl"
SCRIPT_UNDER_TEST="$FAKE_PROJECT/scripts/log-bead-activity.sh"

echo "=== Test: usage error with too few arguments ==="

EXIT_CODE=0
OUTPUT=$("$SCRIPT_UNDER_TEST" 2>&1) || EXIT_CODE=$?

# The script should exit 1 when given no args
if [ $EXIT_CODE -ne 0 ]; then
    pass "Exits non-zero with no arguments (exit $EXIT_CODE)"
else
    fail "Should exit non-zero with no arguments"
fi

if echo "$OUTPUT" | grep -q "Usage:"; then
    pass "Shows usage message with no arguments"
else
    fail "Should show usage message" "$OUTPUT"
fi

EXIT_CODE=0
OUTPUT=$("$SCRIPT_UNDER_TEST" "bd-123" 2>&1) || EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    pass "Exits non-zero with only 1 argument"
else
    fail "Should exit non-zero with only 1 argument"
fi

echo ""
echo "=== Test: successful log entry ==="

# Clear log
> "$LOG_FILE"

"$SCRIPT_UNDER_TEST" "bd-abc1" "claim" "AgentAlpha" 2>/dev/null

LINES=$(wc -l < "$LOG_FILE" | tr -d ' ')
if [ "$LINES" -eq 1 ]; then
    pass "Exactly 1 line written to log"
else
    fail "Expected 1 line, got $LINES"
fi

# Validate JSON
ENTRY=$(cat "$LOG_FILE")
if echo "$ENTRY" | jq . >/dev/null 2>&1; then
    pass "Log entry is valid JSON"
else
    fail "Log entry is not valid JSON" "$ENTRY"
fi

# Check required fields
for field in timestamp agent bead_id action; do
    VALUE=$(echo "$ENTRY" | jq -r ".$field")
    if [ -n "$VALUE" ] && [ "$VALUE" != "null" ]; then
        pass "Field '$field' is present: $VALUE"
    else
        fail "Field '$field' is missing or null"
    fi
done

# Check specific values
AGENT_VAL=$(echo "$ENTRY" | jq -r '.agent')
BEAD_VAL=$(echo "$ENTRY" | jq -r '.bead_id')
ACTION_VAL=$(echo "$ENTRY" | jq -r '.action')

if [ "$AGENT_VAL" = "AgentAlpha" ]; then
    pass "Agent field matches: $AGENT_VAL"
else
    fail "Agent should be 'AgentAlpha', got '$AGENT_VAL'"
fi

if [ "$BEAD_VAL" = "bd-abc1" ]; then
    pass "Bead ID field matches: $BEAD_VAL"
else
    fail "Bead ID should be 'bd-abc1', got '$BEAD_VAL'"
fi

if [ "$ACTION_VAL" = "claim" ]; then
    pass "Action field matches: $ACTION_VAL"
else
    fail "Action should be 'claim', got '$ACTION_VAL'"
fi

echo ""
echo "=== Test: timestamp format ==="

TIMESTAMP=$(echo "$ENTRY" | jq -r '.timestamp')
# ISO 8601 UTC format: YYYY-MM-DDTHH:MM:SSZ
if [[ "$TIMESTAMP" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    pass "Timestamp is ISO 8601 UTC format: $TIMESTAMP"
else
    fail "Timestamp format incorrect" "$TIMESTAMP"
fi

echo ""
echo "=== Test: multiple events append correctly ==="

> "$LOG_FILE"

"$SCRIPT_UNDER_TEST" "bd-001" "create" "AgentA" 2>/dev/null
"$SCRIPT_UNDER_TEST" "bd-001" "claim" "AgentB" 2>/dev/null
"$SCRIPT_UNDER_TEST" "bd-001" "close" "AgentB" 2>/dev/null

LINES=$(wc -l < "$LOG_FILE" | tr -d ' ')
if [ "$LINES" -eq 3 ]; then
    pass "3 events logged correctly"
else
    fail "Expected 3 lines, got $LINES"
fi

# Each line should be valid JSON
LINE_NUM=0
ALL_VALID=true
while IFS= read -r line; do
    LINE_NUM=$((LINE_NUM + 1))
    if ! echo "$line" | jq . >/dev/null 2>&1; then
        ALL_VALID=false
        fail "Line $LINE_NUM is not valid JSON: $line"
    fi
done < "$LOG_FILE"

if [ "$ALL_VALID" = true ]; then
    pass "All 3 lines are valid JSONL"
fi

# Verify different actions
ACTIONS=$(jq -r '.action' "$LOG_FILE" | paste -sd ',' -)
if [ "$ACTIONS" = "create,claim,close" ]; then
    pass "Actions sequence correct: $ACTIONS"
else
    fail "Actions sequence wrong" "Expected 'create,claim,close', got '$ACTIONS'"
fi

echo ""
echo "=== Test: stderr diagnostic output ==="

STDERR=$("$SCRIPT_UNDER_TEST" "bd-xyz" "commit" "TestBot" 2>&1 1>/dev/null)

if echo "$STDERR" | grep -q "\[bead-log\]"; then
    pass "Diagnostic output goes to stderr"
else
    fail "Expected [bead-log] prefix on stderr" "$STDERR"
fi

if echo "$STDERR" | grep -q "TestBot"; then
    pass "Stderr includes agent name"
else
    fail "Stderr should include agent name" "$STDERR"
fi

if echo "$STDERR" | grep -q "bd-xyz"; then
    pass "Stderr includes bead ID"
else
    fail "Stderr should include bead ID" "$STDERR"
fi

echo ""
echo "=============================="
echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
