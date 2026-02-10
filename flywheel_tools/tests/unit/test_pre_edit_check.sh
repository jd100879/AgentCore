#!/usr/bin/env bash
# test_pre_edit_check.sh - Unit tests for pre-edit-check.sh
#
# Tests:
#   1. No arguments → exit 2 with error
#   2. BYPASS_RESERVATION=1 → exit 0 immediately
#   3. Help text mentions exit codes
#
# Usage: ./tests/test_pre_edit_check.sh

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/pre-edit-check.sh"

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

echo "=== Test: no arguments exits with error ==="

EXIT_CODE=0
OUTPUT=$("$SCRIPT" 2>&1) || EXIT_CODE=$?

if [ $EXIT_CODE -eq 2 ]; then
    pass "No arguments exits with code 2"
else
    fail "No arguments should exit 2, got $EXIT_CODE"
fi

if echo "$OUTPUT" | grep -q "Error: No file patterns specified"; then
    pass "Shows 'no file patterns' error"
else
    fail "Should show file patterns error" "$OUTPUT"
fi

if echo "$OUTPUT" | grep -q "USAGE:"; then
    pass "Shows usage information"
else
    fail "Should show usage information"
fi

echo ""
echo "=== Test: usage mentions exit codes ==="

if echo "$OUTPUT" | grep -q "EXIT CODES:"; then
    pass "Usage includes EXIT CODES section"
else
    fail "Usage should include EXIT CODES section"
fi

if echo "$OUTPUT" | grep -q "0 - Files are available"; then
    pass "Documents exit code 0"
else
    fail "Should document exit code 0"
fi

if echo "$OUTPUT" | grep -q "1 - Files are reserved"; then
    pass "Documents exit code 1"
else
    fail "Should document exit code 1"
fi

if echo "$OUTPUT" | grep -q "2 - Error"; then
    pass "Documents exit code 2"
else
    fail "Should document exit code 2"
fi

echo ""
echo "=== Test: BYPASS_RESERVATION=1 skips checks ==="

OUTPUT=$(BYPASS_RESERVATION=1 "$SCRIPT" "src/whatever.py" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    pass "Bypass mode exits with code 0"
else
    fail "Bypass mode should exit 0, got $EXIT_CODE"
fi

if echo "$OUTPUT" | grep -q "bypassed"; then
    pass "Bypass mode shows bypass message"
else
    fail "Should show bypass message" "$OUTPUT"
fi

echo ""
echo "=== Test: BYPASS_RESERVATION=0 does NOT bypass ==="

# With BYPASS_RESERVATION=0, the script should proceed to check
# (will fail since reserve-files.sh requires mail server, but it should NOT bypass)
EXIT_CODE=0
OUTPUT=$(BYPASS_RESERVATION=0 "$SCRIPT" "src/whatever.py" 2>&1) || EXIT_CODE=$?

if echo "$OUTPUT" | grep -q "bypassed"; then
    fail "BYPASS_RESERVATION=0 should NOT bypass"
else
    pass "BYPASS_RESERVATION=0 does not bypass"
fi

echo ""
echo "=== Test: BYPASS_RESERVATION unset does NOT bypass ==="

OUTPUT=$(unset BYPASS_RESERVATION; "$SCRIPT" "src/whatever.py" 2>&1) || true

if echo "$OUTPUT" | grep -q "bypassed"; then
    fail "Unset BYPASS_RESERVATION should NOT bypass"
else
    pass "Unset BYPASS_RESERVATION does not bypass"
fi

echo ""
echo "=== Test: usage shows ENVIRONMENT section ==="

OUTPUT=$("$SCRIPT" 2>&1) || true

if echo "$OUTPUT" | grep -q "ENVIRONMENT:"; then
    pass "Usage includes ENVIRONMENT section"
else
    fail "Usage should include ENVIRONMENT section"
fi

if echo "$OUTPUT" | grep -q "BYPASS_RESERVATION"; then
    pass "Documents BYPASS_RESERVATION variable"
else
    fail "Should document BYPASS_RESERVATION variable"
fi

echo ""
echo "=============================="
echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
