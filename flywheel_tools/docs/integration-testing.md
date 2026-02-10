# Integration Testing Guide for Flywheel Tools

This guide documents integration testing patterns for projects using flywheel_tools components. It covers best practices, common patterns, and examples for writing effective integration tests.

## Table of Contents

1. [Testing Philosophy](#testing-philosophy)
2. [Test Structure](#test-structure)
3. [Unit Tests](#unit-tests)
4. [Integration Tests](#integration-tests)
5. [Common Patterns](#common-patterns)
6. [Test Utilities](#test-utilities)
7. [Best Practices](#best-practices)
8. [Examples](#examples)

## Testing Philosophy

Flywheel tools follows a layered testing approach:

- **Unit tests**: Test individual scripts in isolation
- **Integration tests**: Test multiple components working together in realistic workflows
- **End-to-end tests**: Test complete user scenarios from start to finish

### Key Principles

1. **Deterministic**: Tests should produce the same results every run
2. **Isolated**: Tests should not depend on external state or other tests
3. **Fast**: Unit tests should run quickly; integration tests may take longer
4. **Self-cleaning**: Tests must clean up all artifacts they create
5. **Descriptive**: Test names and output should clearly indicate what's being tested

## Test Structure

### Directory Layout

```
flywheel_tools/
├── tests/
│   ├── unit/               # Unit tests for individual scripts
│   ├── integration/        # Integration tests for workflows
│   ├── fixtures/           # Test data and mock files
│   └── README.md          # Test suite documentation
```

### Standard Test File Structure

```bash
#!/usr/bin/env bash
# Test description and purpose
#
# Tests:
#   1. First test case
#   2. Second test case
#   ...
#
# Usage: ./tests/test_name.sh

set -uo pipefail

# Setup
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/target-script.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
pass() {
    ((TESTS_RUN++))
    ((TESTS_PASSED++))
    echo -e "${GREEN}  ✓ $1${NC}"
}

fail() {
    ((TESTS_RUN++))
    ((TESTS_FAILED++))
    echo -e "${RED}  ✗ $1${NC}"
    [ -n "${2:-}" ] && echo -e "${RED}    $2${NC}"
}

# Create isolated test environment
TMPDIR=$(mktemp -d /tmp/test-name.XXXXXX)
trap "rm -rf '$TMPDIR'" EXIT

# Run tests here...

# Summary
echo ""
echo "Tests run: $TESTS_RUN"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

exit $TESTS_FAILED
```

## Unit Tests

Unit tests verify individual scripts work correctly in isolation.

### Standard Unit Test Pattern

```bash
#!/usr/bin/env bash
# test_script_name.sh - Unit tests for script-name.sh

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/script-name.sh"

# Test helpers (pass, fail, counters)
# ...

echo "=== Test: --help shows usage ==="
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
    fail "--help should show Usage"
fi
```

### What to Test in Unit Tests

1. **Help and usage**: `--help` flag displays usage and exits 0
2. **Argument parsing**: Options are parsed correctly
3. **Error handling**: Invalid inputs produce appropriate errors
4. **Core functions**: Individual functions work as expected
5. **Syntax**: Script has valid bash syntax (`bash -n`)
6. **File operations**: Files are created/modified correctly
7. **Exit codes**: Correct exit codes for success and failure

### Example: Testing Argument Parsing

```bash
echo "=== Test: parse_args sets correct variables ==="

# Mock the script functions
source "$SCRIPT"  # If script allows sourcing

MOCK_ARGS=("--bead" "bd-abc" "--max-restarts" "5")
parse_args "${MOCK_ARGS[@]}"

if [ "$TARGET_BEAD" = "bd-abc" ]; then
    pass "TARGET_BEAD set correctly"
else
    fail "Expected TARGET_BEAD=bd-abc, got $TARGET_BEAD"
fi

if [ "$MAX_RESTARTS" = "5" ]; then
    pass "MAX_RESTARTS set correctly"
else
    fail "Expected MAX_RESTARTS=5, got $MAX_RESTARTS"
fi
```

## Integration Tests

Integration tests verify multiple components work together correctly in realistic scenarios.

### Workflow-Based Testing

Integration tests should simulate real user workflows:

```bash
#!/usr/bin/env bash
# test_phase3_integration.sh - Integration tests for Phase 3 components
#
# Workflows:
#   W1: New Feature Implementation (search → context → work → summary)
#   W2: Bug Investigation (search git → beads → mail → document)
#   W3: Multi-Agent Coordination (swarm → assign → monitor → teardown)

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS_DIR="$PROJECT_ROOT/scripts"

# Test configuration
CLEANUP_SWARMS=()
CLEANUP_TASKS=()
CLEANUP_FILES=()

# Cleanup handler
cleanup() {
    echo "Cleaning up test artifacts..."
    
    # Stop spawned swarms
    for swarm_id in "${CLEANUP_SWARMS[@]}"; do
        "$SCRIPTS_DIR/swarm-teardown.sh" "$swarm_id" 2>/dev/null || true
    done
    
    # Close created tasks
    for task_id in "${CLEANUP_TASKS[@]}"; do
        br close "$task_id" 2>/dev/null || true
    done
    
    # Remove temp files
    for file in "${CLEANUP_FILES[@]}"; do
        rm -f "$file" 2>/dev/null || true
    done
}

trap cleanup EXIT

# Workflow tests...
```

### What to Test in Integration Tests

1. **Component interaction**: Multiple scripts working together
2. **Data flow**: Information correctly passed between components
3. **State management**: Shared state handled correctly
4. **Error propagation**: Errors from one component handled by others
5. **Cleanup**: All components clean up properly
6. **Performance**: Workflows complete in reasonable time

### Example: Multi-Component Workflow

```bash
echo "=== Workflow 1: New Feature Implementation ==="

# W1.1: Search for related code
SEARCH_RESULTS=$("$SCRIPTS_DIR/search-history.sh" "authentication" --format json)
if [ $? -eq 0 ]; then
    pass "W1.1: Code search succeeded"
else
    fail "W1.1: Code search failed"
fi

# W1.2: Create work bead
BEAD_OUTPUT=$("$SCRIPTS_DIR/br-create.sh" "Add OAuth support" --type feature)
BEAD_ID=$(echo "$BEAD_OUTPUT" | grep -oE 'bd-[a-z0-9]+')
CLEANUP_TASKS+=("$BEAD_ID")

if [ -n "$BEAD_ID" ]; then
    pass "W1.2: Bead created: $BEAD_ID"
else
    fail "W1.2: Failed to create bead"
fi

# W1.3: Do work (simulated)
br update "$BEAD_ID" --status in_progress

# W1.4: Generate summary
SUMMARY=$("$SCRIPTS_DIR/summarize-session.sh" --non-interactive --no-commit)
if [ $? -eq 0 ]; then
    pass "W1.4: Session summary generated"
else
    fail "W1.4: Session summary failed"
fi

# W1.5: Close bead
br close "$BEAD_ID"
if [ $? -eq 0 ]; then
    pass "W1.5: Bead closed successfully"
else
    fail "W1.5: Failed to close bead"
fi
```

## Common Patterns

### Pattern 1: Isolated Test Environment

```bash
# Create temporary directory for test
TMPDIR=$(mktemp -d /tmp/test-name.XXXXXX)
export HOME="$TMPDIR"  # Isolate user config
export PROJECT_ROOT="$TMPDIR/project"

# Ensure cleanup
trap "rm -rf '$TMPDIR'" EXIT

# Set up test fixtures
mkdir -p "$PROJECT_ROOT/.beads"
cp tests/fixtures/beads.db "$PROJECT_ROOT/.beads/"
```

### Pattern 2: Mocking External Dependencies

```bash
# Create mock script that replaces real dependency
cat > "$TMPDIR/bin/br" << 'MOCK_BR'
#!/usr/bin/env bash
# Mock br command for testing
case "$1" in
    show)
        echo "bd-test · Test Bead   [OPEN]"
        ;;
    close)
        echo "✓ Closed bd-$2"
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
MOCK_BR

chmod +x "$TMPDIR/bin/br"
export PATH="$TMPDIR/bin:$PATH"
```

### Pattern 3: Fixture Management

```bash
# tests/fixtures/sample-bead.json
{
  "id": "bd-test",
  "title": "Test Bead",
  "status": "open",
  "created_at": "2026-01-01T00:00:00Z"
}

# Load fixture in test
load_fixture() {
    local fixture="$1"
    cat "tests/fixtures/$fixture"
}

BEAD_DATA=$(load_fixture "sample-bead.json")
```

### Pattern 4: Syntax Validation

```bash
test_syntax() {
    local file="$1"
    local name="$2"
    if bash -n "$file" 2>/dev/null; then
        pass "$name syntax valid"
        return 0
    else
        fail "$name syntax error"
        return 1
    fi
}

# Use in tests
test_syntax "$SCRIPTS_DIR/agent-runner.sh" "agent-runner.sh"
```

### Pattern 5: File Existence Checks

```bash
test_file_exists() {
    local file="$1"
    local name="$2"
    if [ -f "$file" ] && [ -x "$file" ]; then
        pass "$name exists and is executable"
        return 0
    elif [ -f "$file" ]; then
        pass "$name exists"
        return 0
    else
        fail "$name missing"
        return 1
    fi
}
```

## Test Utilities

### Shared Test Library

Create `tests/lib/test-helpers.sh` for reusable utilities:

```bash
#!/usr/bin/env bash
# Shared test utilities

# Colors
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m'

# Test result helpers
pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((TESTS_PASSED++))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    [ -n "${2:-}" ] && echo -e "${RED}  $2${NC}"
    ((TESTS_FAILED++))
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# File testing
test_file_exists() {
    local file="$1"
    local name="${2:-$file}"
    [ -f "$file" ] && pass "$name exists" || fail "$name missing"
}

test_executable() {
    local file="$1"
    local name="${2:-$file}"
    [ -x "$file" ] && pass "$name is executable" || fail "$name not executable"
}

test_syntax() {
    local file="$1"
    local name="${2:-$file}"
    bash -n "$file" 2>/dev/null && pass "$name has valid syntax" || fail "$name has syntax errors"
}

# JSON testing
test_json_valid() {
    local file="$1"
    local name="${2:-$file}"
    jq empty "$file" 2>/dev/null && pass "$name is valid JSON" || fail "$name is not valid JSON"
}

# Process testing
test_process_running() {
    local pid="$1"
    local name="${2:-process $pid}"
    ps -p "$pid" >/dev/null 2>&1 && pass "$name is running" || fail "$name is not running"
}

# Setup helpers
create_test_env() {
    TMPDIR=$(mktemp -d /tmp/test-${1}.XXXXXX)
    export TEST_PROJECT_ROOT="$TMPDIR"
    trap "rm -rf '$TMPDIR'" EXIT
    echo "$TMPDIR"
}

# Fixture loading
load_fixture() {
    local fixture="$1"
    local fixtures_dir="${TEST_FIXTURES_DIR:-tests/fixtures}"
    cat "$fixtures_dir/$fixture"
}
```

### Using Test Library

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib/test-helpers.sh"

# Initialize counters
TESTS_PASSED=0
TESTS_FAILED=0

# Create test environment
TEST_DIR=$(create_test_env "mytest")

# Run tests using helpers
test_file_exists "$PROJECT_ROOT/scripts/agent-runner.sh"
test_syntax "$PROJECT_ROOT/scripts/agent-runner.sh"

# Summary
echo ""
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
exit $TESTS_FAILED
```

## Best Practices

### 1. Test Independence

**Good:**
```bash
# Each test creates its own environment
test_feature_a() {
    local tmpdir=$(mktemp -d)
    trap "rm -rf '$tmpdir'" RETURN
    # Test in isolation...
}

test_feature_b() {
    local tmpdir=$(mktemp -d)
    trap "rm -rf '$tmpdir'" RETURN
    # Test in isolation...
}
```

**Bad:**
```bash
# Tests share state
SHARED_DIR="/tmp/shared"
mkdir -p "$SHARED_DIR"

test_feature_a() {
    echo "data" > "$SHARED_DIR/file"
}

test_feature_b() {
    # Depends on test_feature_a running first
    cat "$SHARED_DIR/file"
}
```

### 2. Descriptive Assertions

**Good:**
```bash
if [ "$ACTUAL" = "$EXPECTED" ]; then
    pass "bead status is 'open' after creation"
else
    fail "bead status should be 'open', got '$ACTUAL'"
fi
```

**Bad:**
```bash
if [ "$ACTUAL" = "$EXPECTED" ]; then
    pass "OK"
else
    fail "Failed"
fi
```

### 3. Cleanup Everything

**Good:**
```bash
CLEANUP_BEADS=()
CLEANUP_FILES=()

cleanup() {
    for bead in "${CLEANUP_BEADS[@]}"; do
        br close "$bead" 2>/dev/null || true
    done
    for file in "${CLEANUP_FILES[@]}"; do
        rm -f "$file"
    done
}

trap cleanup EXIT

# Track all created resources
BEAD_ID=$(br create "Test")
CLEANUP_BEADS+=("$BEAD_ID")
```

**Bad:**
```bash
# No cleanup - leaves artifacts
BEAD_ID=$(br create "Test")
# Test runs but never cleans up $BEAD_ID
```

### 4. Test Real Behavior

**Good:**
```bash
# Test actual script execution
OUTPUT=$("$SCRIPTS_DIR/agent-runner.sh" --dry-run --bead bd-test)
if echo "$OUTPUT" | grep -q "Would start agent"; then
    pass "Dry run shows expected output"
fi
```

**Bad:**
```bash
# Test internal implementation details
if grep -q "claude" "$SCRIPTS_DIR/agent-runner.sh"; then
    pass "Script mentions claude"
fi
# This tests the code contains a word, not that it works
```

### 5. Handle Errors Gracefully

**Good:**
```bash
OUTPUT=$("$SCRIPT" --invalid-option 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    pass "Invalid option produces error exit code"
else
    fail "Invalid option should exit non-zero, got $EXIT_CODE"
fi

if echo "$OUTPUT" | grep -qi "error\|unknown"; then
    pass "Error message is shown"
else
    fail "No error message shown" "$OUTPUT"
fi
```

**Bad:**
```bash
# Assumes success
OUTPUT=$("$SCRIPT" --invalid-option)
# Script might have failed but test continues
```

### 6. Test Edge Cases

```bash
# Empty input
test_empty_input() {
    OUTPUT=$("$SCRIPT" "" 2>&1)
    [ $? -ne 0 ] && pass "Empty input rejected" || fail "Should reject empty input"
}

# Very long input
test_long_input() {
    LONG_STRING=$(printf 'a%.0s' {1..10000})
    OUTPUT=$("$SCRIPT" "$LONG_STRING" 2>&1)
    [ $? -eq 0 ] && pass "Handles long input" || fail "Should handle long input"
}

# Special characters
test_special_chars() {
    OUTPUT=$("$SCRIPT" "test'with\"quotes" 2>&1)
    [ $? -eq 0 ] && pass "Handles special chars" || fail "Should handle special chars"
}
```

## Examples

### Example 1: Unit Test for Script Options

```bash
#!/usr/bin/env bash
# test_doctor.sh - Unit tests for doctor.sh

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/doctor.sh"

source "$PROJECT_ROOT/tests/lib/test-helpers.sh"

TESTS_PASSED=0
TESTS_FAILED=0

echo "Testing doctor.sh"
echo "================="

# Test: Script exists and is executable
test_file_exists "$SCRIPT" "doctor.sh"
test_executable "$SCRIPT" "doctor.sh"
test_syntax "$SCRIPT" "doctor.sh"

# Test: --help option
echo ""
echo "Test: --help option"
OUTPUT=$("$SCRIPT" --help 2>&1)
EXIT_CODE=$?

[ $EXIT_CODE -eq 0 ] && pass "--help exits 0" || fail "--help should exit 0"
echo "$OUTPUT" | grep -q "Usage:" && pass "--help shows usage" || fail "--help should show usage"

# Test: --check-deps option
echo ""
echo "Test: --check-deps option"
OUTPUT=$("$SCRIPT" --check-deps 2>&1)
EXIT_CODE=$?

[ $EXIT_CODE -eq 0 ] && pass "--check-deps completes" || warn "--check-deps found issues"
echo "$OUTPUT" | grep -qE "tmux|jq|git" && pass "--check-deps mentions key dependencies"

# Summary
echo ""
echo "Passed: $TESTS_PASSED / $((TESTS_PASSED + TESTS_FAILED))"
exit $TESTS_FAILED
```

### Example 2: Integration Test for Workflow

```bash
#!/usr/bin/env bash
# test_bead_workflow.sh - Integration test for complete bead lifecycle

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PROJECT_ROOT/tests/lib/test-helpers.sh"

TESTS_PASSED=0
TESTS_FAILED=0
CLEANUP_BEADS=()

cleanup() {
    for bead in "${CLEANUP_BEADS[@]}"; do
        br close "$bead" 2>/dev/null || true
    done
}
trap cleanup EXIT

echo "Bead Workflow Integration Test"
echo "=============================="

# Phase 1: Create bead
echo ""
echo "Phase 1: Create bead"
OUTPUT=$(br create "Test integration workflow" --type task 2>&1)
BEAD_ID=$(echo "$OUTPUT" | grep -oE 'bd-[a-z0-9]+' | head -1)

if [ -n "$BEAD_ID" ]; then
    pass "Created bead: $BEAD_ID"
    CLEANUP_BEADS+=("$BEAD_ID")
else
    fail "Failed to create bead"
    exit 1
fi

# Phase 2: Verify bead status
echo ""
echo "Phase 2: Verify initial status"
STATUS=$(br show "$BEAD_ID" | grep -oE '\[OPEN\]')
[ "$STATUS" = "[OPEN]" ] && pass "Bead starts in OPEN status" || fail "Expected OPEN status"

# Phase 3: Start work
echo ""
echo "Phase 3: Start work on bead"
br update "$BEAD_ID" --status in_progress
STATUS=$(br show "$BEAD_ID" | grep -oE '\[IN_PROGRESS\]')
[ "$STATUS" = "[IN_PROGRESS]" ] && pass "Bead moved to IN_PROGRESS" || fail "Status update failed"

# Phase 4: Complete work
echo ""
echo "Phase 4: Complete bead"
br close "$BEAD_ID"
STATUS=$(br show "$BEAD_ID" | grep -oE '\[CLOSED\]')
[ "$STATUS" = "[CLOSED]" ] && pass "Bead closed successfully" || fail "Close failed"

# Phase 5: Verify lifecycle
echo ""
echo "Phase 5: Verify complete lifecycle"
pass "Complete workflow: CREATE → OPEN → IN_PROGRESS → CLOSED"

# Summary
echo ""
echo "Passed: $TESTS_PASSED / $((TESTS_PASSED + TESTS_FAILED))"
exit $TESTS_FAILED
```

### Example 3: Testing with Fixtures

```bash
#!/usr/bin/env bash
# test_mail_system.sh - Test agent mail with fixtures

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures"
source "$PROJECT_ROOT/tests/lib/test-helpers.sh"

TESTS_PASSED=0
TESTS_FAILED=0

# Create test environment
TEST_DIR=$(create_test_env "mail")
export MAIL_DIR="$TEST_DIR/mail"
mkdir -p "$MAIL_DIR"

# Load test fixture
SAMPLE_MAIL=$(load_fixture "sample-mail.json")
echo "$SAMPLE_MAIL" > "$MAIL_DIR/msg-001.json"

# Test: Mail can be read
echo "Test: Read mail"
OUTPUT=$(agent-mail-helper.sh inbox --format json)
if echo "$OUTPUT" | jq -e '.[] | select(.id=="msg-001")' >/dev/null; then
    pass "Mail fixture loaded and readable"
else
    fail "Could not read mail fixture"
fi

# Test: Mail parsing
echo "Test: Parse mail fields"
SUBJECT=$(echo "$OUTPUT" | jq -r '.[0].subject')
if [ "$SUBJECT" = "Test Message" ]; then
    pass "Subject parsed correctly"
else
    fail "Expected subject 'Test Message', got '$SUBJECT'"
fi

# Summary
echo ""
echo "Passed: $TESTS_PASSED / $((TESTS_PASSED + TESTS_FAILED))"
exit $TESTS_FAILED
```

## Running Tests

### Run All Tests

```bash
# Run all unit tests
for test in tests/unit/test_*.sh; do
    echo "Running $test..."
    bash "$test" || echo "FAILED: $test"
done

# Run all integration tests
for test in tests/integration/test_*.sh; do
    echo "Running $test..."
    bash "$test" || echo "FAILED: $test"
done
```

### Run Specific Test Suite

```bash
# Run Phase 1 tests only
bash tests/integration/test-phase1-migration.sh

# Run with verbose output
bash -x tests/unit/test_doctor.sh
```

### Continuous Integration

```bash
#!/usr/bin/env bash
# ci-test.sh - Run all tests and collect results

TOTAL_PASSED=0
TOTAL_FAILED=0

for test_file in tests/**/*.sh; do
    if bash "$test_file"; then
        ((TOTAL_PASSED++))
    else
        ((TOTAL_FAILED++))
        echo "FAILED: $test_file"
    fi
done

echo ""
echo "========================================"
echo "Test Suite Summary"
echo "========================================"
echo "Passed: $TOTAL_PASSED"
echo "Failed: $TOTAL_FAILED"
echo ""

[ $TOTAL_FAILED -eq 0 ] && echo "✓ All tests passed" || echo "✗ Some tests failed"
exit $TOTAL_FAILED
```

## Troubleshooting Tests

### Common Issues

1. **Tests fail locally but pass in CI**
   - Check for environment-specific assumptions (paths, tools)
   - Ensure all dependencies are installed
   - Verify timezone/locale settings

2. **Flaky tests (sometimes pass, sometimes fail)**
   - Look for race conditions (file system, processes)
   - Check for insufficient wait times
   - Ensure proper cleanup between runs

3. **Tests leave artifacts**
   - Add cleanup to trap handlers
   - Use isolated test directories
   - Track all created resources

4. **Mock dependencies not working**
   - Verify PATH precedence
   - Check script uses `command` not absolute paths
   - Ensure mocks are executable

## Contributing Tests

When adding new tests:

1. Follow existing patterns and structure
2. Document what each test verifies
3. Clean up all artifacts
4. Test both success and failure cases
5. Include edge cases
6. Update this documentation if introducing new patterns

## Additional Resources

- [Flywheel Tools README](../README.md)
- [Installation Guide](installation.md)
- [Quick Start Guide](quick-start.md)
- [Unit Test Examples](../tests/unit/)
- [Integration Test Examples](../tests/integration/)

---

**Last Updated**: 2026-02-10  
**Maintained by**: AgentCore Team
