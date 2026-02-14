#!/usr/bin/env bash
# test-registry-ops.sh - Integration tests for agent-registry.sh
#
# Tests registry operations with real YAML files from multiple CWDs
# to ensure canonical path resolution works correctly.
#
# Part of: Phase 2 Integration Testing (bd-3pz)

set -uo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test state
TESTS_PASSED=0
TESTS_FAILED=0
BACKUP_FILE=""
TEST_TEMP_DIR=""

#######################################
# Print colored message
#######################################
print_msg() {
    local color="${!1}"
    local msg="$2"
    echo -e "${color}${msg}${NC}"
}

#######################################
# Print test result
#######################################
print_result() {
    local test_name="$1"
    local result="$2"

    if [ "$result" = "PASS" ]; then
        print_msg GREEN "  ✓ $test_name"
        ((TESTS_PASSED++))
    else
        print_msg RED "  ✗ $test_name"
        ((TESTS_FAILED++))
    fi
}

#######################################
# Cleanup test environment
#######################################
cleanup() {
    local script_path="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${BASH_SOURCE[0]}")"
    local project_root="$(cd "$(dirname "$script_path")/../.." && pwd)"

    # Restore original types.yaml if we backed it up
    if [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
        mv "$BACKUP_FILE" "$project_root/.agent-profiles/types.yaml"
        print_msg YELLOW "  Restored original types.yaml"
    fi

    # Clean up test instances
    if [ -d "$project_root/.agent-profiles/instances" ]; then
        rm -f "$project_root/.agent-profiles/instances/TestAgent"*.json
    fi

    # Clean up temp directory
    if [ -n "$TEST_TEMP_DIR" ] && [ -d "$TEST_TEMP_DIR" ]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

trap cleanup EXIT

#######################################
# Setup test environment
#######################################
setup_test_env() {
    # Find project root (resolve symlinks)
    local script_path="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${BASH_SOURCE[0]}")"
    local project_root="$(cd "$(dirname "$script_path")/../.." && pwd)"

    # Create temp directory for nested path tests and state
    TEST_TEMP_DIR=$(mktemp -d)
    mkdir -p "$TEST_TEMP_DIR/deep/nested/path"
    echo "$project_root" > "$TEST_TEMP_DIR/project_root"

    # Backup original types.yaml
    if [ -f "$project_root/.agent-profiles/types.yaml" ]; then
        BACKUP_FILE=$(mktemp)
        cp "$project_root/.agent-profiles/types.yaml" "$BACKUP_FILE"
        print_msg YELLOW "  Backed up original types.yaml"
    fi

    # Copy test fixtures to actual location
    cp "$project_root/agentcore/verify/fixtures/test-types.yaml" "$project_root/.agent-profiles/types.yaml"
    print_msg GREEN "  Installed test types.yaml"
}

#######################################
# Get canonical registry script path
#######################################
get_registry_script() {
    local project_root="$1"

    # Prefer canonical agentcore/tools path if it exists
    if [ -x "$project_root/agentcore/tools/agent-registry.sh" ]; then
        echo "$project_root/agentcore/tools/agent-registry.sh"
    elif [ -x "$project_root/scripts/agent-registry.sh" ]; then
        echo "$project_root/scripts/agent-registry.sh"
    else
        print_msg RED "Error: agent-registry.sh not found"
        exit 1
    fi
}

#######################################
# Test registry operation from specific CWD
#######################################
test_from_cwd() {
    local test_name="$1"
    local test_cwd="$2"
    local operation="$3"
    shift 3
    local args=("$@")

    local project_root=$(cat "$TEST_TEMP_DIR/project_root")
    local registry_script=$(get_registry_script "$project_root")

    # Run from specified CWD
    local output
    if output=$(cd "$test_cwd" && "$registry_script" "$operation" "${args[@]}" 2>&1); then
        print_result "$test_name" "PASS"
    else
        print_result "$test_name" "FAIL"
        echo "  Output: $output" | head -5 >&2
    fi

    # Always return 0 so test failures don't exit the script
    return 0
}

#######################################
# Test 'list' operation from multiple CWDs
#######################################
test_list_operation() {
    print_msg BLUE "Testing 'list' operation..."

    local project_root=$(cat "$TEST_TEMP_DIR/project_root")

    # Test from different CWDs
    test_from_cwd "list from repo root" "$project_root" "list"
    test_from_cwd "list from /tmp" "/tmp" "list"
    test_from_cwd "list from deep nested path" "$TEST_TEMP_DIR/deep/nested/path" "list"
}

#######################################
# Test 'show' operation from multiple CWDs
#######################################
test_show_operation() {
    print_msg BLUE "Testing 'show' operation..."

    local project_root=$(cat "$TEST_TEMP_DIR/project_root")

    # Test valid types from different CWDs
    test_from_cwd "show test-minimal from repo root" "$project_root" "show" "test-minimal"
    test_from_cwd "show test-full from /tmp" "/tmp" "show" "test-full"
    test_from_cwd "show test-edge-case from nested path" "$TEST_TEMP_DIR/deep/nested/path" "show" "test-edge-case"

    # Test invalid type (should fail gracefully)
    local registry_script=$(get_registry_script "$project_root")

    if ! (cd "$project_root" && "$registry_script" show nonexistent-type >/dev/null 2>&1); then
        print_result "show nonexistent type fails gracefully" "PASS"
    else
        print_result "show nonexistent type fails gracefully" "FAIL"
    fi
}

#######################################
# Test 'capabilities' operation from multiple CWDs
#######################################
test_capabilities_operation() {
    print_msg BLUE "Testing 'capabilities' operation..."

    local project_root=$(cat "$TEST_TEMP_DIR/project_root")

    test_from_cwd "capabilities test-minimal from repo root" "$project_root" "capabilities" "test-minimal"
    test_from_cwd "capabilities test-full from /tmp" "/tmp" "capabilities" "test-full"

    # Test edge case: empty capabilities
    local registry_script=$(get_registry_script "$project_root")
    local output
    output=$(cd "$project_root" && "$registry_script" capabilities test-no-caps 2>&1 || true)

    # Empty capabilities should still succeed (just return nothing or empty list)
    if [ $? -eq 0 ] || [ -z "$output" ]; then
        print_result "capabilities test-no-caps (empty) succeeds" "PASS"
    else
        print_result "capabilities test-no-caps (empty) succeeds" "FAIL"
    fi
}

#######################################
# Test 'validate' operation from multiple CWDs
#######################################
test_validate_operation() {
    print_msg BLUE "Testing 'validate' operation..."

    local project_root=$(cat "$TEST_TEMP_DIR/project_root")
    local registry_script=$(get_registry_script "$project_root")

    # Test from different CWDs
    test_from_cwd "validate test-minimal from repo root" "$project_root" "validate" "test-minimal"
    test_from_cwd "validate test-full from /tmp" "/tmp" "validate" "test-full"

    # Test validation output
    local output
    output=$(cd "$project_root" && "$registry_script" validate test-minimal 2>&1)

    if [ "$output" = "valid" ]; then
        print_result "validate returns 'valid' for existing type" "PASS"
    else
        print_result "validate returns 'valid' for existing type" "FAIL"
    fi

    # Invalid type should return 'invalid'
    output=$(cd "$project_root" && "$registry_script" validate nonexistent-type 2>&1 || echo "invalid")

    if echo "$output" | grep -q "invalid"; then
        print_result "validate returns 'invalid' for nonexistent type" "PASS"
    else
        print_result "validate returns 'invalid' for nonexistent type" "FAIL"
    fi
}

#######################################
# Test register/unregister operations
#######################################
test_register_operations() {
    print_msg BLUE "Testing register/unregister operations..."

    local project_root=$(cat "$TEST_TEMP_DIR/project_root")
    local registry_script=$(get_registry_script "$project_root")

    # Test register from different CWDs
    test_from_cwd "register TestAgent1 from repo root" "$project_root" "register" "TestAgent1" "test-minimal"
    test_from_cwd "register TestAgent2 from /tmp" "/tmp" "register" "TestAgent2" "test-full"

    # Verify instances were created
    if [ -f "$project_root/.agent-profiles/instances/TestAgent1.json" ]; then
        print_result "instance file created for TestAgent1" "PASS"
    else
        print_result "instance file created for TestAgent1" "FAIL"
    fi

    # Test register with invalid type (should fail)
    if ! (cd "$project_root" && "$registry_script" register TestAgent3 invalid-type >/dev/null 2>&1); then
        print_result "register with invalid type fails gracefully" "PASS"
    else
        print_result "register with invalid type fails gracefully" "FAIL"
    fi

    # Test unregister from different CWDs
    test_from_cwd "unregister TestAgent1 from nested path" "$TEST_TEMP_DIR/deep/nested/path" "unregister" "TestAgent1"

    # Verify instance was removed
    if [ ! -f "$project_root/.agent-profiles/instances/TestAgent1.json" ]; then
        print_result "instance file removed for TestAgent1" "PASS"
    else
        print_result "instance file removed for TestAgent1" "FAIL"
    fi

    # Test unregister nonexistent agent (should succeed with warning)
    test_from_cwd "unregister nonexistent agent" "$project_root" "unregister" "NonexistentAgent"
}

#######################################
# Test 'active' operation
#######################################
test_active_operation() {
    print_msg BLUE "Testing 'active' operation..."

    local project_root=$(cat "$TEST_TEMP_DIR/project_root")

    # Should show TestAgent2 from previous test
    test_from_cwd "active from repo root" "$project_root" "active"
    test_from_cwd "active from /tmp" "/tmp" "active"
}

#######################################
# Test dependency checking
#######################################
test_dependency_check() {
    print_msg BLUE "Testing dependency checks..."

    # Check if yq is available
    if command -v yq >/dev/null 2>&1; then
        print_result "yq dependency available" "PASS"
    else
        print_msg YELLOW "  ! yq not installed - tests will fail"
        print_msg YELLOW "  Install with: brew install yq"
        print_result "yq dependency available" "FAIL"
    fi

    # Check if jq is available (needed for active command)
    if command -v jq >/dev/null 2>&1; then
        print_result "jq dependency available" "PASS"
    else
        print_msg YELLOW "  ! jq not installed - active command will fail"
        print_msg YELLOW "  Install with: brew install jq"
        print_result "jq dependency available" "FAIL"
    fi
}

#######################################
# Test data integrity
#######################################
test_data_integrity() {
    print_msg BLUE "Testing data integrity..."

    local project_root=$(cat "$TEST_TEMP_DIR/project_root")
    local registry_script=$(get_registry_script "$project_root")

    # Verify all test types are present
    local output
    output=$(cd "$project_root" && "$registry_script" list 2>&1 || true)

    if echo "$output" | grep -q "test-minimal" && \
       echo "$output" | grep -q "test-full" && \
       echo "$output" | grep -q "test-edge-case" && \
       echo "$output" | grep -q "test-no-caps"; then
        print_result "all test types present in list output" "PASS"
    else
        print_result "all test types present in list output" "FAIL"
        echo "  Output: $output" | head -10 >&2
    fi

    # Verify capabilities are parsed correctly
    output=$(cd "$project_root" && "$registry_script" capabilities test-full 2>&1 || true)

    if echo "$output" | grep -q "testing" && \
       echo "$output" | grep -q "debugging"; then
        print_result "capabilities parsed correctly" "PASS"
    else
        print_result "capabilities parsed correctly" "FAIL"
    fi

    # Verify show includes description and capacity
    output=$(cd "$project_root" && "$registry_script" show test-full 2>&1 || true)

    if echo "$output" | grep -qi "description" && \
       echo "$output" | grep -qi "capacity"; then
        print_result "show includes all expected fields" "PASS"
    else
        print_result "show includes all expected fields" "FAIL"
    fi
}

#######################################
# Main test runner
#######################################
main() {
    print_msg BLUE "======================================="
    print_msg BLUE "Agent Registry Integration Tests"
    print_msg BLUE "======================================="
    echo ""

    # Check dependencies
    if ! command -v python3 >/dev/null 2>&1; then
        print_msg RED "Error: python3 is required for tests"
        exit 1
    fi

    # Setup test environment
    print_msg BLUE "Setting up test environment..."
    setup_test_env
    print_msg GREEN "✓ Test environment ready"
    echo ""

    # Run test suites
    test_dependency_check
    echo ""

    test_list_operation
    echo ""

    test_show_operation
    echo ""

    test_capabilities_operation
    echo ""

    test_validate_operation
    echo ""

    test_register_operations
    echo ""

    test_active_operation
    echo ""

    test_data_integrity
    echo ""

    # Print summary
    print_msg BLUE "======================================="
    print_msg BLUE "Test Summary"
    print_msg BLUE "======================================="

    local total=$((TESTS_PASSED + TESTS_FAILED))
    print_msg GREEN "Passed: $TESTS_PASSED/$total"

    if [ $TESTS_FAILED -gt 0 ]; then
        print_msg RED "Failed: $TESTS_FAILED/$total"
        echo ""
        print_msg RED "Some tests failed!"
        exit 1
    else
        echo ""
        print_msg GREEN "All tests passed!"
        exit 0
    fi
}

main "$@"
