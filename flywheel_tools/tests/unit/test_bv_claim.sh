#!/usr/bin/env bash
# test_bv_claim.sh - Unit tests for bv-claim.sh argument parsing
#
# Tests:
#   1. --help flag shows usage and exits 0
#   2. -h short flag works
#   3. Unknown option produces error
#   4. Argument parsing preserves format and priority options
#
# Usage: ./tests/test_bv_claim.sh

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/bv-claim.sh"

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

echo "=== Test: --help flag ==="

OUTPUT=$("$SCRIPT" --help 2>&1)
EXIT_CODE=$?

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

if echo "$OUTPUT" | grep -q "bv-claim"; then
    pass "--help mentions bv-claim"
else
    fail "--help should mention bv-claim"
fi

if echo "$OUTPUT" | grep -q "\-\-json"; then
    pass "--help documents --json flag"
else
    fail "--help should document --json flag"
fi

if echo "$OUTPUT" | grep -q "\-\-toon"; then
    pass "--help documents --toon flag"
else
    fail "--help should document --toon flag"
fi

if echo "$OUTPUT" | grep -q "\-\-priority"; then
    pass "--help documents --priority flag"
else
    fail "--help should document --priority flag"
fi

echo ""
echo "=== Test: -h short flag ==="

OUTPUT=$("$SCRIPT" -h 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    pass "-h exits with code 0"
else
    fail "-h should exit 0, got $EXIT_CODE"
fi

echo ""
echo "=== Test: unknown option ==="

EXIT_CODE=0
OUTPUT=$("$SCRIPT" --invalid-flag 2>&1) || EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    pass "Unknown option exits non-zero"
else
    fail "Unknown option should exit non-zero"
fi

if echo "$OUTPUT" | grep -qi "error.*unknown option"; then
    pass "Shows error message for unknown option"
else
    fail "Should show error for unknown option" "$OUTPUT"
fi

echo ""
echo "=== Test: required tool checks ==="

# The script checks for bv, br, and jq at startup
# We can verify the error messages by checking the script text
if grep -q "command -v bv" "$SCRIPT"; then
    pass "Script checks for bv command"
else
    fail "Script should check for bv command"
fi

if grep -q "command -v br" "$SCRIPT"; then
    pass "Script checks for br command"
else
    fail "Script should check for br command"
fi

if grep -q "command -v jq" "$SCRIPT"; then
    pass "Script checks for jq command"
else
    fail "Script should check for jq command"
fi

echo ""
echo "=== Test: script validates agent identity ==="

# Check that the script validates the agent identity pattern
if grep -q 'AGENT_NAME.*whoami' "$SCRIPT"; then
    pass "Script gets agent name via whoami"
else
    fail "Script should get agent name via whoami"
fi

if grep -q 'Cannot claim beads without.*registered agent' "$SCRIPT"; then
    pass "Script validates agent identity"
else
    fail "Script should validate agent identity"
fi

echo ""
echo "=== Test: script handles in-progress tasks ==="

if grep -q "already in progress" "$SCRIPT"; then
    pass "Script detects in-progress tasks"
else
    fail "Script should detect in-progress tasks"
fi

echo ""
echo "=== Test: script handles TOON format ==="

if grep -q "TOON" "$SCRIPT"; then
    pass "Script supports TOON format"
else
    fail "Script should support TOON format"
fi

echo ""
echo "=============================="
echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
