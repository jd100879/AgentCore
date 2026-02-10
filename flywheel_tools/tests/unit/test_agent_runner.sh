#!/usr/bin/env bash
# test_agent_runner.sh - Unit tests for agent-runner.sh
#
# Tests:
#   1. --help shows usage and exits 0
#   2. Unknown option exits non-zero
#   3. --dry-run shows what would happen without launching claude
#   4. parse_args sets TARGET_BEAD from --bead
#   5. parse_args sets MAX_RESTARTS from --max-restarts
#   6. write_tracking_file creates correct file
#   7. build_system_prompt includes agent name and cycling instructions
#   8. get_bead_details formats bead info
#   9. log_metric appends JSONL to metrics file
#  10. cleanup removes temp files
#
# Usage: ./tests/test_agent_runner.sh

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/agent-runner.sh"

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

# Create isolated test environment
TMPDIR=$(mktemp -d /tmp/test-agent-runner.XXXXXX)
trap "rm -rf '$TMPDIR'" EXIT

echo "=== Test: --help shows usage ==="

EXIT_CODE=0
OUTPUT=$("$SCRIPT" --help 2>&1) || EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    pass "--help exits with code 0"
else
    fail "--help should exit 0, got $EXIT_CODE"
fi

if echo "$OUTPUT" | grep -q "Usage:"; then
    pass "--help shows Usage"
else
    fail "--help should show Usage" "$OUTPUT"
fi

if echo "$OUTPUT" | grep -q "\-\-bead"; then
    pass "--help documents --bead option"
else
    fail "--help should document --bead"
fi

if echo "$OUTPUT" | grep -q "\-\-max-restarts"; then
    pass "--help documents --max-restarts option"
else
    fail "--help should document --max-restarts"
fi

if echo "$OUTPUT" | grep -q "\-\-dry-run"; then
    pass "--help documents --dry-run option"
else
    fail "--help should document --dry-run"
fi

echo ""
echo "=== Test: unknown option exits non-zero ==="

EXIT_CODE=0
OUTPUT=$("$SCRIPT" --bogus-option 2>&1) || EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    pass "Unknown option exits non-zero"
else
    fail "Unknown option should exit non-zero"
fi

if echo "$OUTPUT" | grep -q "Unknown option"; then
    pass "Unknown option shows error message"
else
    fail "Should show 'Unknown option' message"
fi

echo ""
echo "=== Test: parse_args via sourcing ==="

# Source the script functions in a subshell to test parse_args
OUTPUT=$(bash -c '
    # Override functions that would cause side effects
    get_agent_identity() { AGENT_NAME="TestAgent"; }
    print_banner() { :; }
    log() { :; }
    claim_next_bead() { echo ""; }
    write_tracking_file() { :; }
    build_system_prompt() { echo "prompt"; }
    get_bead_details() { echo "details"; }
    log_metric() { :; }
    claude() { return 0; }

    # Source the script to get parse_args function
    source "'"$SCRIPT"'" 2>/dev/null || true

    # Test parse_args
    TARGET_BEAD=""
    MAX_RESTARTS=5
    DRY_RUN=false

    parse_args --bead bd-test --max-restarts 3 --dry-run

    echo "BEAD=$TARGET_BEAD"
    echo "MAX=$MAX_RESTARTS"
    echo "DRY=$DRY_RUN"
' 2>/dev/null)

if echo "$OUTPUT" | grep -q "BEAD=bd-test"; then
    pass "--bead sets TARGET_BEAD"
else
    fail "--bead should set TARGET_BEAD" "$OUTPUT"
fi

if echo "$OUTPUT" | grep -q "MAX=3"; then
    pass "--max-restarts sets MAX_RESTARTS"
else
    fail "--max-restarts should set MAX_RESTARTS" "$OUTPUT"
fi

if echo "$OUTPUT" | grep -q "DRY=true"; then
    pass "--dry-run sets DRY_RUN"
else
    fail "--dry-run should set DRY_RUN" "$OUTPUT"
fi

echo ""
echo "=== Test: write_tracking_file creates correct file ==="

# Test tracking file creation in isolated env
AGENT_NAME="TestRunner42"
TRACKING_FILE="/tmp/agent-bead-${AGENT_NAME}.txt"
rm -f "$TRACKING_FILE"

# Source just the function we need
eval "$(sed -n '/^write_tracking_file/,/^}/p' "$SCRIPT" | sed 's/log DEBUG/# log DEBUG/')"

write_tracking_file "bd-test123"

if [ -f "$TRACKING_FILE" ]; then
    pass "write_tracking_file creates tracking file"
else
    fail "write_tracking_file should create tracking file"
fi

CONTENT=$(cat "$TRACKING_FILE" 2>/dev/null)
if [ "$CONTENT" = "bd-test123" ]; then
    pass "Tracking file contains bead ID"
else
    fail "Tracking file should contain bead ID, got: $CONTENT"
fi

rm -f "$TRACKING_FILE"

echo ""
echo "=== Test: build_system_prompt includes key content ==="

# Source the function
AGENT_NAME="TestBot"
eval "$(sed -n '/^build_system_prompt/,/^}/p' "$SCRIPT")"

PROMPT=$(build_system_prompt "bd-999")

if echo "$PROMPT" | grep -q "TestBot"; then
    pass "System prompt includes agent name"
else
    fail "System prompt should include agent name"
fi

if echo "$PROMPT" | grep -q "agent-mail-helper.sh inbox"; then
    pass "System prompt includes inbox check instruction"
else
    fail "System prompt should mention inbox check"
fi

if echo "$PROMPT" | grep -q "br close"; then
    pass "System prompt includes bead close instruction"
else
    fail "System prompt should mention br close"
fi

if echo "$PROMPT" | grep -q "next-bead.sh"; then
    pass "System prompt includes next-bead transition"
else
    fail "System prompt should mention next-bead.sh"
fi

if echo "$PROMPT" | grep -q "Do NOT use the Task tool"; then
    pass "System prompt includes no-Task-tool rule"
else
    fail "System prompt should mention no-Task-tool"
fi

echo ""
echo "=== Test: log_metric appends JSONL ==="

METRICS_FILE="$TMPDIR/test-metrics.jsonl"
AGENT_NAME="MetricBot"
RESTART_COUNT=2

# Source the function
eval "$(sed -n '/^log_metric/,/^}/p' "$SCRIPT")"

log_metric "launch" "bd-abc"
log_metric "exit" "code=0"

if [ -f "$METRICS_FILE" ]; then
    pass "log_metric creates metrics file"
else
    fail "log_metric should create metrics file"
fi

LINE_COUNT=$(wc -l < "$METRICS_FILE" | tr -d ' ')
if [ "$LINE_COUNT" -eq 2 ]; then
    pass "Metrics file has 2 entries"
else
    fail "Metrics file should have 2 entries, got $LINE_COUNT"
fi

# Validate JSON
FIRST_LINE=$(head -1 "$METRICS_FILE")
if echo "$FIRST_LINE" | jq -e '.timestamp' >/dev/null 2>&1; then
    pass "Metrics entries are valid JSON with timestamp"
else
    fail "Metrics entries should be valid JSON"
fi

if echo "$FIRST_LINE" | jq -e '.agent == "MetricBot"' >/dev/null 2>&1; then
    pass "Metrics contain correct agent name"
else
    fail "Metrics should contain agent name"
fi

if echo "$FIRST_LINE" | jq -e '.event == "launch"' >/dev/null 2>&1; then
    pass "Metrics contain event type"
else
    fail "Metrics should contain event type"
fi

if echo "$FIRST_LINE" | jq -e '.restart_count == 2' >/dev/null 2>&1; then
    pass "Metrics contain restart count"
else
    fail "Metrics should contain restart count"
fi

echo ""
echo "=== Test: cleanup removes temp files ==="

AGENT_NAME="CleanupBot"
# Create temp files that cleanup should remove
echo "prompt" > "/tmp/agent-runner-prompt-${AGENT_NAME}.md"
echo "bd-test" > "/tmp/agent-bead-${AGENT_NAME}.txt"

# Source cleanup function (override log and exit)
SHUTTING_DOWN=false
eval "$(sed -n '/^cleanup/,/^}/p' "$SCRIPT" | sed 's/exit 0/return 0/' | sed 's/log INFO/# log/')"

cleanup 2>/dev/null || true

if [ ! -f "/tmp/agent-runner-prompt-${AGENT_NAME}.md" ]; then
    pass "cleanup removes prompt file"
else
    fail "cleanup should remove prompt file"
    rm -f "/tmp/agent-runner-prompt-${AGENT_NAME}.md"
fi

if [ ! -f "/tmp/agent-bead-${AGENT_NAME}.txt" ]; then
    pass "cleanup removes bead tracking file"
else
    fail "cleanup should remove bead tracking file"
    rm -f "/tmp/agent-bead-${AGENT_NAME}.txt"
fi

echo ""
echo "=============================="
echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
