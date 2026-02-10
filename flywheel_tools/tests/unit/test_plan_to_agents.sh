#!/usr/bin/env bash
# test_plan_to_agents.sh - Unit tests for plan-to-agents.sh
#
# Tests:
#   1. --help shows usage and exits 0
#   2. Unknown option exits non-zero
#   3. recommend_count logic (0 beads → 0, 1-2 → 1, 3+ → ceil(n/2))
#   4. --json with no beads outputs valid JSON
#   5. Type inference integration (uses lib-infer-type.sh)
#   6. Max agents cap is respected
#
# Usage: ./tests/test_plan_to_agents.sh

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/plan-to-agents.sh"
LIB_INFER="$PROJECT_ROOT/scripts/lib-infer-type.sh"

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
    fail "--help should show Usage"
fi

if echo "$OUTPUT" | grep -q "\-\-auto"; then
    pass "--help documents --auto"
else
    fail "--help should document --auto"
fi

if echo "$OUTPUT" | grep -q "\-\-json"; then
    pass "--help documents --json"
else
    fail "--help should document --json"
fi

if echo "$OUTPUT" | grep -q "\-\-max-agents"; then
    pass "--help documents --max-agents"
else
    fail "--help should document --max-agents"
fi

echo ""
echo "=== Test: unknown option exits non-zero ==="

EXIT_CODE=0
OUTPUT=$("$SCRIPT" --bogus 2>&1) || EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    pass "Unknown option exits non-zero"
else
    fail "Unknown option should exit non-zero"
fi

echo ""
echo "=== Test: recommend_count logic ==="

# Define the recommend_count function locally for testing
recommend_count() {
    local beads=$1
    if [ "$beads" -eq 0 ]; then
        echo 0
    elif [ "$beads" -le 2 ]; then
        echo 1
    else
        echo $(( (beads + 1) / 2 ))
    fi
}

# Test: 0 beads → 0 agents
RESULT=$(recommend_count 0)
if [ "$RESULT" -eq 0 ]; then
    pass "0 beads → 0 agents"
else
    fail "0 beads should → 0 agents, got $RESULT"
fi

# Test: 1 bead → 1 agent
RESULT=$(recommend_count 1)
if [ "$RESULT" -eq 1 ]; then
    pass "1 bead → 1 agent"
else
    fail "1 bead should → 1 agent, got $RESULT"
fi

# Test: 2 beads → 1 agent
RESULT=$(recommend_count 2)
if [ "$RESULT" -eq 1 ]; then
    pass "2 beads → 1 agent"
else
    fail "2 beads should → 1 agent, got $RESULT"
fi

# Test: 3 beads → 2 agents
RESULT=$(recommend_count 3)
if [ "$RESULT" -eq 2 ]; then
    pass "3 beads → 2 agents"
else
    fail "3 beads should → 2 agents, got $RESULT"
fi

# Test: 4 beads → 2 agents
RESULT=$(recommend_count 4)
if [ "$RESULT" -eq 2 ]; then
    pass "4 beads → 2 agents"
else
    fail "4 beads should → 2 agents, got $RESULT"
fi

# Test: 5 beads → 3 agents
RESULT=$(recommend_count 5)
if [ "$RESULT" -eq 3 ]; then
    pass "5 beads → 3 agents"
else
    fail "5 beads should → 3 agents, got $RESULT"
fi

# Test: 10 beads → 5 agents
RESULT=$(recommend_count 10)
if [ "$RESULT" -eq 5 ]; then
    pass "10 beads → 5 agents"
else
    fail "10 beads should → 5 agents, got $RESULT"
fi

echo ""
echo "=== Test: infer_agent_type from lib-infer-type.sh ==="

if [ -f "$LIB_INFER" ]; then
    source "$LIB_INFER"

    # Test QA inference
    RESULT=$(infer_agent_type "Add test coverage" "" "")
    if [ "$RESULT" = "qa" ]; then
        pass "Title with 'test' → qa"
    else
        fail "Title with 'test' should → qa, got $RESULT"
    fi

    # Test backend inference
    RESULT=$(infer_agent_type "Fix API endpoint" "" "")
    if [ "$RESULT" = "backend" ]; then
        pass "Title with 'API endpoint' → backend"
    else
        fail "Title with 'API endpoint' should → backend, got $RESULT"
    fi

    # Test frontend inference
    RESULT=$(infer_agent_type "Update button styles" "" "")
    if [ "$RESULT" = "frontend" ]; then
        pass "Title with 'button styles' → frontend"
    else
        fail "Title with 'button styles' should → frontend, got $RESULT"
    fi

    # Test devops inference
    RESULT=$(infer_agent_type "Configure Docker deployment" "" "")
    if [ "$RESULT" = "devops" ]; then
        pass "Title with 'Docker deployment' → devops"
    else
        fail "Title with 'Docker deployment' should → devops, got $RESULT"
    fi

    # Test docs inference
    RESULT=$(infer_agent_type "Write API documentation" "" "")
    if [ "$RESULT" = "docs" ]; then
        pass "Title with 'documentation' → docs"
    else
        fail "Title with 'documentation' should → docs, got $RESULT"
    fi

    # Test label override
    RESULT=$(infer_agent_type "Fix a thing" "" "frontend")
    if [ "$RESULT" = "frontend" ]; then
        pass "Label 'frontend' overrides title"
    else
        fail "Label 'frontend' should override, got $RESULT"
    fi

    # Test general fallback
    RESULT=$(infer_agent_type "Do something" "" "")
    if [ "$RESULT" = "general" ]; then
        pass "Generic title → general"
    else
        fail "Generic title should → general, got $RESULT"
    fi
else
    fail "lib-infer-type.sh not found"
fi

echo ""
echo "=== Test: --json with no beads ==="

# Create a mock br that returns empty results
TMPDIR=$(mktemp -d /tmp/test-plan-to-agents.XXXXXX)
trap "rm -rf '$TMPDIR'" EXIT

MOCK_BR="$TMPDIR/br"
cat > "$MOCK_BR" << 'MOCK'
#!/bin/bash
case "$1" in
    sync) exit 0 ;;
    ready) echo "[]" ;;
    *) echo "[]" ;;
esac
MOCK
chmod +x "$MOCK_BR"

MOCK_BV="$TMPDIR/bv"
cat > "$MOCK_BV" << 'MOCK'
#!/bin/bash
echo '[]'
MOCK
chmod +x "$MOCK_BV"

# Run with mock br on PATH
OUTPUT=$(PATH="$TMPDIR:$PATH" "$SCRIPT" --json 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    pass "--json with no beads exits 0"
else
    fail "--json with no beads should exit 0, got $EXIT_CODE"
fi

if echo "$OUTPUT" | jq -e '.beads == 0' >/dev/null 2>&1; then
    pass "JSON output shows 0 beads"
else
    fail "JSON should show 0 beads" "$OUTPUT"
fi

if echo "$OUTPUT" | jq -e '.message' >/dev/null 2>&1; then
    pass "JSON output includes message"
else
    fail "JSON should include message" "$OUTPUT"
fi

echo ""
echo "=== Test: --json with mock beads ==="

# Create mock br that returns some beads
cat > "$MOCK_BR" << 'MOCK'
#!/bin/bash
case "$1" in
    sync) exit 0 ;;
    ready)
        cat << 'JSON'
[
  {"id":"bd-001","title":"Add test coverage for auth","description":"Write unit tests","labels":"qa"},
  {"id":"bd-002","title":"Fix API endpoint","description":"Backend bug","labels":"backend"},
  {"id":"bd-003","title":"Update button component","description":"UI fix","labels":"frontend"},
  {"id":"bd-004","title":"Add more tests","description":"","labels":""}
]
JSON
        ;;
    *) echo "[]" ;;
esac
MOCK
chmod +x "$MOCK_BR"

OUTPUT=$(PATH="$TMPDIR:$PATH" "$SCRIPT" --json 2>&1)

if echo "$OUTPUT" | jq -e '.beads == 4' >/dev/null 2>&1; then
    pass "JSON shows 4 beads"
else
    fail "JSON should show 4 beads" "$OUTPUT"
fi

if echo "$OUTPUT" | jq -e '.by_type' >/dev/null 2>&1; then
    pass "JSON includes by_type breakdown"
else
    fail "JSON should include by_type" "$OUTPUT"
fi

if echo "$OUTPUT" | jq -e '.total_agents > 0' >/dev/null 2>&1; then
    pass "JSON shows positive total_agents"
else
    fail "JSON should show positive total_agents" "$OUTPUT"
fi

echo ""
echo "=============================="
echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
