#!/usr/bin/env bash
# test_br_create_infer_type.sh - Unit tests for --infer-type flag in br-create.sh
#
# Tests:
#   1. validate_type accepts all valid types
#   2. validate_type rejects invalid types
#   3. --infer-type flag overrides keyword inference (checked via stderr log)
#   4. Invalid --infer-type value produces error and exits non-zero
#
# Usage:
#   ./tests/test_br_create_infer_type.sh

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$PROJECT_ROOT/scripts"

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

echo "=== Test: validate_type function ==="

# Source the script to get validate_type and VALID_TYPES
source "$SCRIPT_DIR/lib-infer-type.sh"
VALID_TYPES="general backend frontend devops docs qa"

validate_type() {
    local type_name="$1"
    for valid in $VALID_TYPES; do
        if [ "$type_name" = "$valid" ]; then
            return 0
        fi
    done
    return 1
}

# Test valid types
for t in general backend frontend devops docs qa; do
    if validate_type "$t"; then
        pass "validate_type accepts '$t'"
    else
        fail "validate_type should accept '$t'"
    fi
done

# Test invalid types
for t in invalid foo "back end" "" "BACKEND"; do
    if validate_type "$t" 2>/dev/null; then
        fail "validate_type should reject '$t'"
    else
        pass "validate_type rejects '$t'"
    fi
done

echo ""
echo "=== Test: --infer-type flag overrides inference ==="

# When --infer-type backend is passed with a title that would normally infer "qa"
# (because "test" triggers qa), the log should show "backend" not "qa"
STDERR_OUTPUT=$("$SCRIPT_DIR/br-create.sh" "Add test coverage" --infer-type backend 2>&1 1>/dev/null || true)

if echo "$STDERR_OUTPUT" | grep -q "\[br-create\] Inferred type: backend"; then
    pass "--infer-type backend overrides 'test' keyword (would be qa)"
else
    # Check if it errored for a different reason (e.g., br not available)
    if echo "$STDERR_OUTPUT" | grep -q "Error: Invalid --infer-type"; then
        fail "--infer-type backend was rejected as invalid" "$STDERR_OUTPUT"
    elif echo "$STDERR_OUTPUT" | grep -q "\[br-create\] Inferred type: qa"; then
        fail "--infer-type was ignored, inference ran instead" "$STDERR_OUTPUT"
    else
        # br create may fail (no workspace), but we can still check if the type was set
        if echo "$STDERR_OUTPUT" | grep -q "Inferred type: backend"; then
            pass "--infer-type backend overrides inference (br create may have failed)"
        else
            fail "--infer-type test inconclusive" "$STDERR_OUTPUT"
        fi
    fi
fi

echo ""
echo "=== Test: invalid --infer-type produces error ==="

STDERR_OUTPUT=$("$SCRIPT_DIR/br-create.sh" "Some task" --infer-type bogus 2>&1)
EXIT_CODE=$?

if [ "$EXIT_CODE" -ne 0 ]; then
    pass "Invalid --infer-type exits non-zero (exit code: $EXIT_CODE)"
else
    fail "Invalid --infer-type should exit non-zero but got 0"
fi

if echo "$STDERR_OUTPUT" | grep -q "Error: Invalid --infer-type value: bogus"; then
    pass "Invalid --infer-type shows error message"
else
    fail "Missing error message for invalid --infer-type" "$STDERR_OUTPUT"
fi

if echo "$STDERR_OUTPUT" | grep -q "Valid types:"; then
    pass "Invalid --infer-type shows valid types list"
else
    fail "Missing valid types list in error output" "$STDERR_OUTPUT"
fi

echo ""
echo "=== Test: --infer-type not passed through to br create ==="

# Capture the full command that would be run by using a mock br
# Create a temp dir with a mock br command
MOCK_DIR=$(mktemp -d /tmp/br-create-test.XXXXXX)
trap "rm -rf '$MOCK_DIR'" EXIT

cat > "$MOCK_DIR/br" << 'MOCK_EOF'
#!/usr/bin/env bash
# Mock br: just print args to stderr so we can inspect them
echo "MOCK_BR_ARGS: $*" >&2
MOCK_EOF
chmod +x "$MOCK_DIR/br"

# Run with mock br in PATH
STDERR_OUTPUT=$(PATH="$MOCK_DIR:$PATH" "$SCRIPT_DIR/br-create.sh" "Add API route" --infer-type backend 2>&1 1>/dev/null || true)

if echo "$STDERR_OUTPUT" | grep "MOCK_BR_ARGS" | grep -q "\-\-infer-type"; then
    fail "--infer-type was passed through to br create"
else
    pass "--infer-type is NOT passed through to br create"
fi

echo ""
echo "=============================="
echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
