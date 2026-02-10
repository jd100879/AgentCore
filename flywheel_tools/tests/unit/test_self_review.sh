#!/usr/bin/env bash
# Integration tests for self-review tool (bd-24f)
# Run with: ./tests/test_self_review.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SELF_REVIEW="$PROJECT_ROOT/scripts/self-review.sh"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_result() {
    local name="$1"
    local expected="$2"
    local actual="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ "$actual" == "$expected" ]]; then
        echo -e "${GREEN}✓${NC} $name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} $name (expected: $expected, got: $actual)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

test_contains() {
    local name="$1"
    local needle="$2"
    local haystack="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    if echo "$haystack" | grep -q "$needle"; then
        echo -e "${GREEN}✓${NC} $name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} $name (expected to find: '$needle')"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

echo "Testing self-review tool (bd-24f)"
echo "=================================="
echo ""

# Test 1: Script exists and is executable
echo "Test Suite 1: Basic Checks"
echo "---------------------------"

if [[ -f "$SELF_REVIEW" ]]; then
    echo -e "${GREEN}✓${NC} Script exists"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} Script exists"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_RUN=$((TESTS_RUN + 1))

if [[ -x "$SELF_REVIEW" ]]; then
    echo -e "${GREEN}✓${NC} Script is executable"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} Script is executable"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_RUN=$((TESTS_RUN + 1))

echo ""

# Test 2: Max iterations blocking (exit code 2)
echo "Test Suite 2: Iteration Limits"
echo "-------------------------------"

# Iteration 4 should be blocked
set +e
output=$(echo "" | "$SELF_REVIEW" --iteration 4 2>&1)
exit_code=$?
set -e
test_result "Iteration 4 blocked with exit code 2" "2" "$exit_code"
test_contains "Iteration 4 shows max iterations message" "Maximum review iterations" "$output"

# Iteration 5 should also be blocked
set +e
output=$(echo "" | "$SELF_REVIEW" --iteration 5 2>&1)
exit_code=$?
set -e
test_result "Iteration 5 blocked with exit code 2" "2" "$exit_code"

echo ""

# Test 3: Valid iterations don't immediately fail
echo "Test Suite 3: Valid Iterations"
echo "-------------------------------"

# Provide enough 'y' input to get through all interactive prompts
FAKE_INPUT=$(printf 'y%.0s' {1..50})

for i in 1 2 3; do
    set +e
    output=$(echo "$FAKE_INPUT" | "$SELF_REVIEW" --iteration $i 2>&1 | head -50)
    exit_code=$?
    set -e

    # Should NOT exit with code 2 (that's for max iterations)
    # Exit codes: 0=passed, 1=issues (for automated checks), 141=SIGPIPE from yes|head
    if [[ $exit_code -ne 2 ]]; then
        echo -e "${GREEN}✓${NC} Iteration $i not blocked (exit code: $exit_code)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Iteration $i should not be blocked"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))

    # Should show correct iteration number
    test_contains "Iteration $i shows 'Iteration $i/3'" "Iteration $i/3" "$output"
done

echo ""

# Test 4: Time limits display correctly
echo "Test Suite 4: Time Limits"
echo "-------------------------"

# Use printf to provide stdin; set +e since self-review exits non-zero
FAKE_INPUT=$(printf 'y%.0s' {1..50})
set +e

output=$(echo "$FAKE_INPUT" | "$SELF_REVIEW" --iteration 1 2>&1 | head -30)
test_contains "Iteration 1 shows 5 minute limit" "5 minutes" "$output"

output=$(echo "$FAKE_INPUT" | "$SELF_REVIEW" --iteration 2 2>&1 | head -30)
test_contains "Iteration 2 shows 3 minute limit" "3 minutes" "$output"

output=$(echo "$FAKE_INPUT" | "$SELF_REVIEW" --iteration 3 2>&1 | head -30)
test_contains "Iteration 3 shows 2 minute limit" "2 minutes" "$output"

set -e

echo ""

# Test 5: Checklist sections present
echo "Test Suite 5: Checklist Sections"
echo "---------------------------------"

set +e
output=$(echo "$FAKE_INPUT" | "$SELF_REVIEW" 2>&1 | head -100)
set -e

test_contains "Code Quality section present" "Code Quality" "$output"
test_contains "Testing section present" "esting" "$output"  # Matches "Testing" or "testing"
test_contains "Documentation section present" "Documentation" "$output"
test_contains "Safety/Governance section present" "Safety\|Governance" "$output"

echo ""

# Test 6: Documentation exists
echo "Test Suite 6: Documentation"
echo "---------------------------"

DOC_PATH="$PROJECT_ROOT/docs/self-review-guide.md"
if [[ -f "$DOC_PATH" ]]; then
    echo -e "${GREEN}✓${NC} Documentation file exists"
    TESTS_PASSED=$((TESTS_PASSED + 1))

    doc_content=$(cat "$DOC_PATH")
    test_contains "Documentation has Quick Start" "Quick Start\|quick start" "$doc_content"
    test_contains "Documentation mentions time-boxing" "ime\|iteration" "$doc_content"
    test_contains "Documentation has examples" "xample" "$doc_content"
    test_contains "Documentation references governance" "governance" "$doc_content"
else
    echo -e "${RED}✗${NC} Documentation file exists"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_RUN=$((TESTS_RUN + 1))

echo ""

# Test 7: Acceptance criteria
echo "Test Suite 7: Acceptance Criteria (bd-24f)"
echo "------------------------------------------"

# Criterion 1: Tool runs successfully
set +e
output=$(echo "$FAKE_INPUT" | "$SELF_REVIEW" 2>&1)
exit_code=$?
set -e
if [[ $exit_code -eq 0 ]] || [[ $exit_code -eq 1 ]] || [[ $exit_code -eq 141 ]]; then
    echo -e "${GREEN}✓${NC} Tool runs successfully (exit code: $exit_code)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗${NC} Tool should exit cleanly (got exit code: $exit_code)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Criterion 2: Provides actionable feedback
test_contains "Provides actionable feedback" "Next steps\|Options" "$output"

# Criterion 3: Time limits prevent runaway
set +e
output=$(echo "" | "$SELF_REVIEW" --iteration 4 2>&1)
exit_code=$?
set -e
test_result "Time limits prevent runaway (blocks iteration 4+)" "2" "$exit_code"
test_contains "Explains max iterations" "Maximum" "$output"

# Criterion 4: Integration with workflows
if [[ -f "$DOC_PATH" ]]; then
    doc_content=$(cat "$DOC_PATH")
    test_contains "Integrates with file reservations" "reserve" "$doc_content"
    test_contains "Integrates with git workflow" "commit" "$doc_content"
fi

echo ""
echo "=================================="
echo "Test Summary"
echo "=================================="
echo "Tests run:    $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    echo ""
    echo -e "${RED}Some tests failed${NC}"
    exit 1
else
    echo -e "Tests failed: ${GREEN}0${NC}"
    echo ""
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
