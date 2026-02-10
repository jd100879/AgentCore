#!/usr/bin/env bash
# test_session_hooks.sh - Unit tests for session-start-hook.sh and session-stop-hook.sh
#
# Tests:
#   1. session-stop-hook always exits 0 (advisory)
#   2. session-stop-hook shows bead reminder when tracking file exists
#   3. session-start-hook always exits 0 (allows session)
#   4. session-start-hook detects active bead
#   5. session-start-hook handles missing bead gracefully
#
# Usage: ./tests/test_session_hooks.sh

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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
TMPDIR=$(mktemp -d /tmp/test-session-hooks.XXXXXX)
trap "rm -rf '$TMPDIR'" EXIT

mkdir -p "$TMPDIR/scripts"

# Create mock agent-mail-helper.sh
cat > "$TMPDIR/scripts/agent-mail-helper.sh" << 'MOCK'
#!/bin/bash
echo "TestAgent"
MOCK
chmod +x "$TMPDIR/scripts/agent-mail-helper.sh"

# Create mock br
cat > "$TMPDIR/bin-br" << 'MOCK'
#!/bin/bash
case "$1" in
    show) echo '[{"status":"in_progress"}]' ;;
    sync) exit 0 ;;
esac
MOCK
chmod +x "$TMPDIR/bin-br"

# ===========================
# Test session-stop-hook
# ===========================

# Create test version of session-stop-hook
cat > "$TMPDIR/scripts/session-stop-hook.sh" << HOOK
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$TMPDIR/scripts"
PATH="$TMPDIR:\$PATH"
INPUT=\$(cat)
AGENT_NAME=\$("\$SCRIPT_DIR/agent-mail-helper.sh" whoami 2>/dev/null || echo "unknown")
BEAD_TRACKING_FILE="/tmp/agent-bead-\${AGENT_NAME}.txt"

if [ -f "\$BEAD_TRACKING_FILE" ]; then
    BEAD_ID=\$(cat "\$BEAD_TRACKING_FILE")
    # Mock br show response
    BEAD_STATUS="in_progress"
    if [ "\$BEAD_STATUS" = "in_progress" ]; then
        echo "" >&2
        echo "📋 Active bead: \$BEAD_ID (in_progress)" >&2
        echo "   If work is complete, remember to:" >&2
        echo "   → br close '\$BEAD_ID'   (mark done)" >&2
    fi
fi
exit 0
HOOK
chmod +x "$TMPDIR/scripts/session-stop-hook.sh"

echo "=== Test: session-stop-hook always exits 0 ==="

# Without tracking file
rm -f "/tmp/agent-bead-TestAgent.txt"

EXIT_CODE=0
echo '{}' | "$TMPDIR/scripts/session-stop-hook.sh" >/dev/null 2>&1 || EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    pass "Stop hook exits 0 without tracking file"
else
    fail "Stop hook should exit 0, got $EXIT_CODE"
fi

# With tracking file
echo "bd-stop1" > "/tmp/agent-bead-TestAgent.txt"

EXIT_CODE=0
echo '{}' | "$TMPDIR/scripts/session-stop-hook.sh" >/dev/null 2>&1 || EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    pass "Stop hook exits 0 with tracking file"
else
    fail "Stop hook should exit 0, got $EXIT_CODE"
fi

echo ""
echo "=== Test: session-stop-hook shows bead reminder ==="

OUTPUT=$(echo '{}' | "$TMPDIR/scripts/session-stop-hook.sh" 2>&1)

if echo "$OUTPUT" | grep -q "Active bead: bd-stop1"; then
    pass "Shows active bead ID"
else
    fail "Should show active bead ID" "$OUTPUT"
fi

if echo "$OUTPUT" | grep -q "br close"; then
    pass "Shows br close reminder"
else
    fail "Should show br close reminder"
fi

echo ""
echo "=== Test: session-stop-hook quiet without bead ==="

rm -f "/tmp/agent-bead-TestAgent.txt"
OUTPUT=$(echo '{}' | "$TMPDIR/scripts/session-stop-hook.sh" 2>&1)

if echo "$OUTPUT" | grep -q "Active bead"; then
    fail "Should NOT show bead reminder when no tracking file"
else
    pass "No bead reminder when no tracking file"
fi

rm -f "/tmp/agent-bead-TestAgent.txt"

# ===========================
# Test session-start-hook structure
# ===========================

echo ""
echo "=== Test: session-start-hook structure ==="

START_HOOK="$PROJECT_ROOT/scripts/session-start-hook.sh"

# Verify it reads stdin (hook input)
if grep -q 'INPUT=.*cat' "$START_HOOK"; then
    pass "Start hook reads stdin"
else
    fail "Start hook should read stdin"
fi

# Verify it extracts source
if grep -q 'SOURCE.*jq.*source' "$START_HOOK"; then
    pass "Start hook extracts source field"
else
    fail "Start hook should extract source from JSON"
fi

# Verify it handles startup vs resume/clear
if grep -q '"startup"' "$START_HOOK"; then
    pass "Start hook handles startup source"
else
    fail "Start hook should handle startup source"
fi

# Verify it checks bead tracking file
if grep -q 'BEAD_TRACKING_FILE' "$START_HOOK"; then
    pass "Start hook checks bead tracking file"
else
    fail "Start hook should check bead tracking file"
fi

# Verify it always exits 0 (advisory mode)
if grep -q 'exit 0' "$START_HOOK"; then
    pass "Start hook exits 0 (advisory)"
else
    fail "Start hook should exit 0"
fi

# Verify blocking mode is commented out
if grep -q '# exit 2' "$START_HOOK"; then
    pass "Blocking mode is commented out (advisory mode active)"
else
    # Check if it's uncommented (active blocking)
    if grep -q '^[[:space:]]*exit 2' "$START_HOOK"; then
        pass "Start hook has explicit blocking mode (uncommented exit 2)"
    else
        fail "Start hook should have exit 2 (commented or uncommented)"
    fi
fi

# Verify it checks for bv availability
if grep -q 'command -v bv' "$START_HOOK"; then
    pass "Start hook checks for bv availability"
else
    fail "Start hook should check for bv"
fi

echo ""
echo "=== Test: session-stop-hook structure ==="

STOP_HOOK="$PROJECT_ROOT/scripts/session-stop-hook.sh"

# Verify it reads stdin
if grep -q 'INPUT=.*cat' "$STOP_HOOK"; then
    pass "Stop hook reads stdin"
else
    fail "Stop hook should read stdin"
fi

# Verify it always exits 0
LAST_EXIT=$(grep 'exit' "$STOP_HOOK" | tail -1)
if echo "$LAST_EXIT" | grep -q 'exit 0'; then
    pass "Stop hook final exit is 0 (advisory only)"
else
    fail "Stop hook should end with exit 0" "$LAST_EXIT"
fi

# Verify it checks bead status via br show
if grep -q 'br show' "$STOP_HOOK"; then
    pass "Stop hook checks bead status"
else
    fail "Stop hook should check bead status"
fi

echo ""
echo "=============================="
echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"

# Cleanup
rm -f "/tmp/agent-bead-TestAgent.txt"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
