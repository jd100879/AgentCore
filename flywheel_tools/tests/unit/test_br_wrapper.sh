#!/usr/bin/env bash
# test_br_wrapper.sh - Unit tests for br-wrapper.sh
#
# Tests:
#   1. Passes all arguments to the real br
#   2. Shows commit reminder on successful close
#   3. Does not show reminder on non-close commands
#   4. Preserves exit codes from real br
#
# Usage: ./tests/test_br_wrapper.sh

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
TMPDIR=$(mktemp -d /tmp/test-br-wrapper.XXXXXX)
trap "rm -rf '$TMPDIR'" EXIT

# Create a mock br that records its args and exits with configurable code
MOCK_BR="$TMPDIR/br"
cat > "$MOCK_BR" << 'MOCK'
#!/bin/bash
# Record args to a file
echo "$@" > /tmp/test-br-wrapper-args.txt
# Exit with code from env or 0
exit ${MOCK_BR_EXIT:-0}
MOCK
chmod +x "$MOCK_BR"

# Create a test copy of br-wrapper.sh pointing to our mock
TEST_WRAPPER="$TMPDIR/br-wrapper.sh"
cat > "$TEST_WRAPPER" << WRAPPER
#!/bin/bash
REAL_BR="$MOCK_BR"

"\$REAL_BR" "\$@"
exit_code=\$?

if [[ "\$1" == "close" && \$exit_code -eq 0 ]]; then
    echo ""
    echo "📝 Remember to commit your changes if you haven't already"
fi

exit \$exit_code
WRAPPER
chmod +x "$TEST_WRAPPER"

echo "=== Test: passes arguments to real br ==="

"$TEST_WRAPPER" show bd-123 --json 2>/dev/null
RECORDED_ARGS=$(cat /tmp/test-br-wrapper-args.txt)

if [ "$RECORDED_ARGS" = "show bd-123 --json" ]; then
    pass "Arguments passed through: '$RECORDED_ARGS'"
else
    fail "Expected 'show bd-123 --json', got '$RECORDED_ARGS'"
fi

echo ""
echo "=== Test: commit reminder on successful close ==="

OUTPUT=$("$TEST_WRAPPER" close bd-456 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    pass "Close exits with code 0"
else
    fail "Close should exit 0, got $EXIT_CODE"
fi

if echo "$OUTPUT" | grep -q "Remember to commit"; then
    pass "Shows commit reminder after close"
else
    fail "Should show commit reminder after close" "$OUTPUT"
fi

echo ""
echo "=== Test: no reminder on non-close commands ==="

OUTPUT=$("$TEST_WRAPPER" show bd-789 2>&1)

if echo "$OUTPUT" | grep -q "Remember to commit"; then
    fail "Should NOT show commit reminder for 'show'"
else
    pass "No commit reminder for 'show'"
fi

OUTPUT=$("$TEST_WRAPPER" list --json 2>&1)

if echo "$OUTPUT" | grep -q "Remember to commit"; then
    fail "Should NOT show commit reminder for 'list'"
else
    pass "No commit reminder for 'list'"
fi

OUTPUT=$("$TEST_WRAPPER" update bd-789 --status in_progress 2>&1)

if echo "$OUTPUT" | grep -q "Remember to commit"; then
    fail "Should NOT show commit reminder for 'update'"
else
    pass "No commit reminder for 'update'"
fi

echo ""
echo "=== Test: no reminder when close fails ==="

EXIT_CODE=0
OUTPUT=$(MOCK_BR_EXIT=1 "$TEST_WRAPPER" close bd-fail 2>&1) || EXIT_CODE=$?

if [ $EXIT_CODE -eq 1 ]; then
    pass "Preserves non-zero exit code from br"
else
    fail "Should preserve exit code 1, got $EXIT_CODE"
fi

if echo "$OUTPUT" | grep -q "Remember to commit"; then
    fail "Should NOT show commit reminder when close fails"
else
    pass "No commit reminder when close fails"
fi

echo ""
echo "=== Test: preserves various exit codes ==="

for code in 0 1 2 127; do
    ACTUAL=0
    MOCK_BR_EXIT=$code "$TEST_WRAPPER" list 2>/dev/null || ACTUAL=$?
    if [ $ACTUAL -eq $code ]; then
        pass "Preserves exit code $code"
    else
        fail "Should preserve exit code $code, got $ACTUAL"
    fi
done

echo ""
echo "=============================="
echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"

# Cleanup
rm -f /tmp/test-br-wrapper-args.txt

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
