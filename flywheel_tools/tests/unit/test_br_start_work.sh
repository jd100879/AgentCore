#!/usr/bin/env bash
# test_br_start_work.sh - Unit tests for br-start-work.sh argument parsing
#
# Tests argument parsing and validation logic without requiring
# external tools (br, bv, jq) or agent registration.
#
# Usage: ./tests/test_br_start_work.sh

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/br-start-work.sh"

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

if echo "$OUTPUT" | grep -q "br-start-work"; then
    pass "--help shows script name"
else
    fail "--help should show script name" "$OUTPUT"
fi

if echo "$OUTPUT" | grep -q "Usage:"; then
    pass "--help shows usage section"
else
    fail "--help should show Usage section"
fi

if echo "$OUTPUT" | grep -q "\-\-type"; then
    pass "--help documents --type flag"
else
    fail "--help should document --type flag"
fi

if echo "$OUTPUT" | grep -q "\-\-priority"; then
    pass "--help documents --priority flag"
else
    fail "--help should document --priority flag"
fi

if echo "$OUTPUT" | grep -q "\-\-dry-run"; then
    pass "--help documents --dry-run flag"
else
    fail "--help should document --dry-run flag"
fi

if echo "$OUTPUT" | grep -q "\-\-force"; then
    pass "--help documents --force flag"
else
    fail "--help should document --force flag"
fi

if echo "$OUTPUT" | grep -q "\-\-resume"; then
    pass "--help documents --resume flag"
else
    fail "--help should document --resume flag"
fi

if echo "$OUTPUT" | grep -q "\-\-claim-existing"; then
    pass "--help documents --claim-existing flag"
else
    fail "--help should document --claim-existing flag"
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

if echo "$OUTPUT" | grep -q "Usage:"; then
    pass "-h shows usage"
else
    fail "-h should show usage"
fi

echo ""
echo "=== Test: unknown option ==="

EXIT_CODE=0
OUTPUT=$("$SCRIPT" --nonexistent 2>&1) || EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    pass "Unknown option exits non-zero"
else
    fail "Unknown option should exit non-zero"
fi

if echo "$OUTPUT" | grep -qi "error.*unknown option"; then
    pass "Shows error for unknown option"
else
    fail "Should show error for unknown option" "$OUTPUT"
fi

echo ""
echo "=== Test: multiple titles error ==="

# The script should reject two positional args
EXIT_CODE=0
OUTPUT=$("$SCRIPT" "Title One" "Title Two" 2>&1) || EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    pass "Multiple titles exit non-zero"
else
    fail "Multiple titles should exit non-zero"
fi

if echo "$OUTPUT" | grep -qi "multiple titles"; then
    pass "Shows error about multiple titles"
else
    fail "Should mention multiple titles in error" "$OUTPUT"
fi

echo ""
echo "=== Test: required tools check ==="

# Create a mock environment without br/bv/jq to test tool check
MOCK_DIR=$(mktemp -d /tmp/br-start-test.XXXXXX)
trap "rm -rf '$MOCK_DIR'" EXIT

# Mock agent-mail-helper to return a valid agent name
mkdir -p "$MOCK_DIR/scripts"
cat > "$MOCK_DIR/scripts/agent-mail-helper.sh" << 'MOCK'
#!/bin/bash
echo "TestAgent"
MOCK
chmod +x "$MOCK_DIR/scripts/agent-mail-helper.sh"

# Run with PATH that lacks br/bv/jq (use a minimal PATH)
EXIT_CODE=0
OUTPUT=$(PATH="/usr/bin:/bin" "$SCRIPT" "Test" 2>&1) || EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    pass "Exits non-zero when required tools missing"
else
    # Some systems may have all tools; skip this check
    echo -e "  - Skipped: all required tools present on this system"
fi

echo ""
echo "=============================="
echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
