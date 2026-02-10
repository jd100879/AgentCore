#!/usr/bin/env bash
# test_agent_registry.sh - Unit tests for agent-registry.sh
#
# Tests:
#   1. help/usage output
#   2. validate returns valid/invalid correctly
#   3. register creates instance file with correct JSON
#   4. unregister removes instance file
#   5. active lists registered agents
#   6. unknown command error
#   7. missing argument errors
#
# Usage: ./tests/test_agent_registry.sh

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/agent-registry.sh"

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

# Check if yq is available (needed by agent-registry.sh)
if ! command -v yq &>/dev/null; then
    echo "SKIP: yq is not installed (required by agent-registry.sh)"
    echo "Install with: brew install yq"
    exit 0
fi

echo "=== Test: help shows usage ==="

EXIT_CODE=0
OUTPUT=$("$SCRIPT" help 2>&1) || EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    pass "help exits with code 0"
else
    fail "help should exit 0, got $EXIT_CODE"
fi

if echo "$OUTPUT" | grep -q "Usage:"; then
    pass "help shows Usage"
else
    fail "help should show Usage" "$OUTPUT"
fi

if echo "$OUTPUT" | grep -q "list"; then
    pass "help documents list command"
else
    fail "help should document list command"
fi

if echo "$OUTPUT" | grep -q "register"; then
    pass "help documents register command"
else
    fail "help should document register command"
fi

echo ""
echo "=== Test: no args shows usage and exits 1 ==="

EXIT_CODE=0
OUTPUT=$("$SCRIPT" 2>&1) || EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    pass "No args exits non-zero"
else
    fail "No args should exit non-zero"
fi

echo ""
echo "=== Test: unknown command ==="

EXIT_CODE=0
OUTPUT=$("$SCRIPT" bogus 2>&1) || EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    pass "Unknown command exits non-zero"
else
    fail "Unknown command should exit non-zero"
fi

echo ""
echo "=== Test: validate accepts known types ==="

for t in general backend frontend devops docs qa; do
    OUTPUT=$("$SCRIPT" validate "$t" 2>/dev/null)
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 0 ] && [ "$OUTPUT" = "valid" ]; then
        pass "validate '$t' → valid"
    else
        fail "validate '$t' should be valid, got exit=$EXIT_CODE output='$OUTPUT'"
    fi
done

echo ""
echo "=== Test: validate rejects unknown types ==="

for t in invalid foo "back end" ml security; do
    EXIT_CODE=0
    OUTPUT=$("$SCRIPT" validate "$t" 2>/dev/null) || EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ] && [ "$OUTPUT" = "invalid" ]; then
        pass "validate '$t' → invalid"
    else
        fail "validate '$t' should be invalid, got exit=$EXIT_CODE output='$OUTPUT'"
    fi
done

echo ""
echo "=== Test: validate missing argument ==="

EXIT_CODE=0
OUTPUT=$("$SCRIPT" validate 2>&1) || EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    pass "validate without arg exits non-zero"
else
    fail "validate without arg should exit non-zero"
fi

echo ""
echo "=== Test: list shows agent types ==="

OUTPUT=$("$SCRIPT" list 2>/dev/null)

if echo "$OUTPUT" | grep -q "general"; then
    pass "list includes general type"
else
    fail "list should include general type" "$OUTPUT"
fi

if echo "$OUTPUT" | grep -q "backend"; then
    pass "list includes backend type"
else
    fail "list should include backend type"
fi

echo ""
echo "=== Test: show displays type details ==="

OUTPUT=$("$SCRIPT" show backend 2>/dev/null)

if echo "$OUTPUT" | grep -q "Agent Type: backend"; then
    pass "show backend displays type header"
else
    fail "show should display type header" "$OUTPUT"
fi

if echo "$OUTPUT" | grep -q "Capabilities"; then
    pass "show displays capabilities section"
else
    fail "show should display capabilities"
fi

echo ""
echo "=== Test: show unknown type ==="

EXIT_CODE=0
OUTPUT=$("$SCRIPT" show nonexistent 2>&1) || EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    pass "show unknown type exits non-zero"
else
    fail "show unknown type should exit non-zero"
fi

echo ""
echo "=== Test: capabilities lists type capabilities ==="

OUTPUT=$("$SCRIPT" capabilities backend 2>/dev/null)

if echo "$OUTPUT" | grep -q "python\|api\|database"; then
    pass "capabilities shows backend skills"
else
    fail "capabilities should show backend skills" "$OUTPUT"
fi

echo ""
echo "=== Test: register/unregister lifecycle ==="

INSTANCES_DIR="$PROJECT_ROOT/.agent-profiles/instances"

# Register a test agent
OUTPUT=$("$SCRIPT" register TestBot99 backend 2>&1)

INSTANCE_FILE="$INSTANCES_DIR/TestBot99.json"
if [ -f "$INSTANCE_FILE" ]; then
    pass "register creates instance file"
else
    fail "register should create instance file"
fi

# Verify JSON content
if [ -f "$INSTANCE_FILE" ]; then
    NAME=$(jq -r '.name' "$INSTANCE_FILE")
    TYPE=$(jq -r '.type' "$INSTANCE_FILE")
    STATUS=$(jq -r '.status' "$INSTANCE_FILE")

    if [ "$NAME" = "TestBot99" ]; then
        pass "Instance file has correct name"
    else
        fail "Name should be TestBot99, got $NAME"
    fi

    if [ "$TYPE" = "backend" ]; then
        pass "Instance file has correct type"
    else
        fail "Type should be backend, got $TYPE"
    fi

    if [ "$STATUS" = "active" ]; then
        pass "Instance file has active status"
    else
        fail "Status should be active, got $STATUS"
    fi
fi

# Check active list includes our agent
OUTPUT=$("$SCRIPT" active 2>/dev/null)

if echo "$OUTPUT" | grep -q "TestBot99"; then
    pass "active includes registered agent"
else
    fail "active should include TestBot99" "$OUTPUT"
fi

# Unregister
OUTPUT=$("$SCRIPT" unregister TestBot99 2>&1)

if [ ! -f "$INSTANCE_FILE" ]; then
    pass "unregister removes instance file"
else
    fail "unregister should remove instance file"
    rm -f "$INSTANCE_FILE"  # cleanup
fi

echo ""
echo "=== Test: register invalid type ==="

EXIT_CODE=0
OUTPUT=$("$SCRIPT" register TestBotBad invalidtype 2>&1) || EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    pass "register with invalid type exits non-zero"
else
    fail "register with invalid type should exit non-zero"
    # cleanup in case it was created
    rm -f "$INSTANCES_DIR/TestBotBad.json"
fi

echo ""
echo "=== Test: register missing args ==="

EXIT_CODE=0
OUTPUT=$("$SCRIPT" register 2>&1) || EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    pass "register without args exits non-zero"
else
    fail "register without args should exit non-zero"
fi

echo ""
echo "=== Test: unregister nonexistent agent ==="

EXIT_CODE=0
OUTPUT=$("$SCRIPT" unregister NoSuchAgent999 2>&1) || EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    pass "unregister nonexistent agent exits 0 (graceful)"
else
    fail "unregister nonexistent should exit 0 (warning only), got $EXIT_CODE"
fi

echo ""
echo "=== Test: types alias ==="

OUTPUT=$("$SCRIPT" types 2>/dev/null)

if echo "$OUTPUT" | grep -q "Available Agent Types"; then
    pass "'types' is alias for 'list'"
else
    fail "'types' should be alias for 'list'" "$OUTPUT"
fi

echo ""
echo "=============================="
echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
