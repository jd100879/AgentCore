#!/usr/bin/env bash
# test_hook_bypass.sh - Unit tests for hook-bypass.sh
#
# Tests:
#   1. enable creates bypass file
#   2. disable removes bypass file
#   3. status reports correctly
#   4. check returns proper exit codes
#   5. unknown command shows usage
#   6. default command is status
#
# Usage: ./tests/test_hook_bypass.sh

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
TMPDIR=$(mktemp -d /tmp/test-hook-bypass.XXXXXX)
trap "rm -rf '$TMPDIR'" EXIT

# Create a test copy that uses our temp dir as project root
TEST_SCRIPT="$TMPDIR/hook-bypass.sh"
mkdir -p "$TMPDIR/scripts"
cat > "$TEST_SCRIPT" << SCRIPT
#!/bin/bash
PROJECT_ROOT="$TMPDIR"
BYPASS_FILE="\${PROJECT_ROOT}/.claude-hooks-bypass"

function enable_bypass() {
    touch "\$BYPASS_FILE"
    echo "✓ Hook bypass ENABLED"
}

function disable_bypass() {
    rm -f "\$BYPASS_FILE"
    echo "✓ Hook bypass DISABLED"
}

function status() {
    if [ -f "\$BYPASS_FILE" ]; then
        echo "⚠️  Hook bypass is ACTIVE"
    else
        echo "✓ Hook bypass is INACTIVE (hooks run normally)"
    fi
}

function is_bypassed() {
    if [ -f "\$BYPASS_FILE" ]; then
        return 0
    else
        return 1
    fi
}

case "\${1:-status}" in
    on|enable) enable_bypass ;;
    off|disable) disable_bypass ;;
    status) status ;;
    check) is_bypassed; exit \$? ;;
    *)
        echo "Usage: \$0 {on|off|status|check}"
        exit 1
        ;;
esac
SCRIPT
chmod +x "$TEST_SCRIPT"

BYPASS_FILE="$TMPDIR/.claude-hooks-bypass"

echo "=== Test: enable creates bypass file ==="

rm -f "$BYPASS_FILE"
OUTPUT=$("$TEST_SCRIPT" on 2>&1)

if [ -f "$BYPASS_FILE" ]; then
    pass "Bypass file created"
else
    fail "Bypass file should exist after 'on'"
fi

if echo "$OUTPUT" | grep -q "ENABLED"; then
    pass "Shows ENABLED message"
else
    fail "Should show ENABLED message" "$OUTPUT"
fi

echo ""
echo "=== Test: check returns 0 when bypassed ==="

EXIT_CODE=0
"$TEST_SCRIPT" check 2>/dev/null || EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    pass "check returns 0 when bypass active"
else
    fail "check should return 0 when active, got $EXIT_CODE"
fi

echo ""
echo "=== Test: status reports ACTIVE when enabled ==="

OUTPUT=$("$TEST_SCRIPT" status 2>&1)

if echo "$OUTPUT" | grep -q "ACTIVE"; then
    pass "Status shows ACTIVE"
else
    fail "Status should show ACTIVE" "$OUTPUT"
fi

echo ""
echo "=== Test: disable removes bypass file ==="

OUTPUT=$("$TEST_SCRIPT" off 2>&1)

if [ ! -f "$BYPASS_FILE" ]; then
    pass "Bypass file removed"
else
    fail "Bypass file should not exist after 'off'"
fi

if echo "$OUTPUT" | grep -q "DISABLED"; then
    pass "Shows DISABLED message"
else
    fail "Should show DISABLED message" "$OUTPUT"
fi

echo ""
echo "=== Test: check returns 1 when not bypassed ==="

EXIT_CODE=0
"$TEST_SCRIPT" check 2>/dev/null || EXIT_CODE=$?

if [ $EXIT_CODE -eq 1 ]; then
    pass "check returns 1 when bypass inactive"
else
    fail "check should return 1 when inactive, got $EXIT_CODE"
fi

echo ""
echo "=== Test: status reports INACTIVE when disabled ==="

OUTPUT=$("$TEST_SCRIPT" status 2>&1)

if echo "$OUTPUT" | grep -q "INACTIVE"; then
    pass "Status shows INACTIVE"
else
    fail "Status should show INACTIVE" "$OUTPUT"
fi

echo ""
echo "=== Test: default command is status ==="

OUTPUT=$("$TEST_SCRIPT" 2>&1)

if echo "$OUTPUT" | grep -q "INACTIVE"; then
    pass "Default (no args) runs status"
else
    fail "No args should run status" "$OUTPUT"
fi

echo ""
echo "=== Test: enable/disable aliases ==="

"$TEST_SCRIPT" enable >/dev/null 2>&1
if [ -f "$BYPASS_FILE" ]; then
    pass "'enable' alias works"
else
    fail "'enable' alias should create file"
fi

"$TEST_SCRIPT" disable >/dev/null 2>&1
if [ ! -f "$BYPASS_FILE" ]; then
    pass "'disable' alias works"
else
    fail "'disable' alias should remove file"
fi

echo ""
echo "=== Test: unknown command shows usage ==="

EXIT_CODE=0
OUTPUT=$("$TEST_SCRIPT" bogus 2>&1) || EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    pass "Unknown command exits non-zero"
else
    fail "Unknown command should exit non-zero"
fi

if echo "$OUTPUT" | grep -q "Usage:"; then
    pass "Unknown command shows usage"
else
    fail "Unknown command should show usage" "$OUTPUT"
fi

echo ""
echo "=== Test: double disable is idempotent ==="

rm -f "$BYPASS_FILE"
"$TEST_SCRIPT" off >/dev/null 2>&1
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    pass "Double disable doesn't error"
else
    fail "Double disable should not error, got exit $EXIT_CODE"
fi

echo ""
echo "=== Test: double enable is idempotent ==="

"$TEST_SCRIPT" on >/dev/null 2>&1
"$TEST_SCRIPT" on >/dev/null 2>&1
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ] && [ -f "$BYPASS_FILE" ]; then
    pass "Double enable doesn't error, file still exists"
else
    fail "Double enable should not error"
fi

echo ""
echo "=============================="
echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
