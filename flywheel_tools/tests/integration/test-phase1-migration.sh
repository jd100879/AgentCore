#!/usr/bin/env bash
# Integration test for Phase 1 migration
# Tests core agent infrastructure scripts in flywheel_tools

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLYWHEEL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CORE_DIR="$FLYWHEEL_ROOT/scripts/core"
HOOKS_DIR="$FLYWHEEL_ROOT/scripts/hooks"
LIB_DIR="$FLYWHEEL_ROOT/scripts/lib"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((TESTS_PASSED++))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    ((TESTS_FAILED++))
}

test_file_exists() {
    local file="$1"
    local name="$2"
    if [ -f "$file" ]; then
        pass "$name exists"
        return 0
    else
        fail "$name missing"
        return 1
    fi
}

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

echo "Phase 1 Migration - Integration Test"
echo "====================================="
echo ""

# Test lib files
test_file_exists "$LIB_DIR/project-config.sh" "project-config.sh" && test_syntax "$LIB_DIR/project-config.sh" "project-config.sh"
test_file_exists "$LIB_DIR/pane-init.sh" "pane-init.sh" && test_syntax "$LIB_DIR/pane-init.sh" "pane-init.sh"

# Test core scripts
test_file_exists "$CORE_DIR/agent-runner.sh" "agent-runner.sh" && test_syntax "$CORE_DIR/agent-runner.sh" "agent-runner.sh"
test_file_exists "$CORE_DIR/next-bead.sh" "next-bead.sh" && test_syntax "$CORE_DIR/next-bead.sh" "next-bead.sh"
test_file_exists "$CORE_DIR/wake-agents.sh" "wake-agents.sh" && test_syntax "$CORE_DIR/wake-agents.sh" "wake-agents.sh"

# Test hooks
for hook in session-start-hook.sh session-stop-hook.sh pre-edit-check-hook.sh pre-edit-check.sh \
            pre-bash-bead-check-hook.sh post-bash-bead-track-hook.sh \
            post-bead-close-hook.sh pre-task-block-hook.sh; do
    test_file_exists "$HOOKS_DIR/$hook" "$hook" && test_syntax "$HOOKS_DIR/$hook" "$hook"
done

echo ""
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
[ $TESTS_FAILED -eq 0 ] && echo "✓ All tests PASSED" && exit 0
echo "✗ Some tests FAILED" && exit 1
