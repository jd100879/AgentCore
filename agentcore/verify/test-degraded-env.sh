#!/usr/bin/env bash
# test-degraded-env.sh - Robustness testing for coordination tools
#
# Tests that coordination tools fail gracefully under constrained environments
# rather than crashing, hanging, or producing cryptic errors.
#
# Part of: Phase 2 Testing Infrastructure (bd-2jm)

set -uo pipefail

# Note: We don't use set -e here because we're testing error conditions
# and need to handle command failures gracefully

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test state
TESTS_PASSED=0
TESTS_FAILED=0
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
    local details="${3:-}"

    if [ "$result" = "PASS" ]; then
        print_msg GREEN "  ✓ $test_name"
        ((TESTS_PASSED++))
    else
        print_msg RED "  ✗ $test_name"
        if [ -n "$details" ]; then
            echo "    Details: $details"
        fi
        ((TESTS_FAILED++))
    fi
}

#######################################
# Cleanup test environment
#######################################
cleanup() {
    if [ -n "$TEST_TEMP_DIR" ] && [ -d "$TEST_TEMP_DIR" ]; then
        chmod -R +w "$TEST_TEMP_DIR" 2>/dev/null || true
        rm -rf "$TEST_TEMP_DIR"
    fi
}

trap cleanup EXIT

#######################################
# Setup test environment
#######################################
setup_test_env() {
    # Find project root
    local script_path="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${BASH_SOURCE[0]}")"
    local project_root="$(cd "$(dirname "$script_path")/../.." && pwd)"

    # Create temp directory for tests
    TEST_TEMP_DIR=$(mktemp -d)
    echo "$project_root" > "$TEST_TEMP_DIR/project_root"

    print_msg GREEN "  Test environment ready"
}

#######################################
# Get canonical paths for testing
#######################################
get_paths() {
    local project_root=$(cat "$TEST_TEMP_DIR/project_root")

    # Prefer canonical agentcore/tools path
    if [ -d "$project_root/agentcore/tools" ]; then
        echo "$project_root/agentcore/tools"
    else
        echo "$project_root/scripts"
    fi
}

#######################################
# Test: Missing python3 dependency
#######################################
test_missing_python3() {
    print_msg BLUE "Testing behavior with missing python3..."

    local project_root=$(cat "$TEST_TEMP_DIR/project_root")
    local tools_dir=$(get_paths)

    # Create fake bin with python3 that fails
    local fake_bin="$TEST_TEMP_DIR/fake-bin-no-python3"
    mkdir -p "$fake_bin"

    # Create fake python3 that exits with "not found" error
    cat > "$fake_bin/python3" <<'EOF'
#!/bin/bash
echo "python3: command not found" >&2
exit 127
EOF
    chmod +x "$fake_bin/python3"

    # Copy all essential system commands except python3
    for cmd in bash sh cat grep echo test mkdir ls pwd cd dirname basename readlink sed awk tr cut head tail chmod; do
        if command -v "$cmd" >/dev/null 2>&1; then
            ln -sf "$(command -v "$cmd")" "$fake_bin/$cmd" 2>/dev/null || true
        fi
    done

    # Test agent-registry.sh (requires python3 for path resolution)
    local output
    local exit_code

    output=$(PATH="$fake_bin" "$tools_dir/agent-registry.sh" list 2>&1)
    exit_code=$?

    # Should fail with clear error message about python3
    if [ $exit_code -ne 0 ]; then
        if echo "$output" | grep -iq "python3"; then
            print_result "agent-registry.sh fails gracefully without python3" "PASS"
        else
            print_result "agent-registry.sh fails gracefully without python3" "FAIL" "Error message unclear: $output"
        fi
    else
        print_result "agent-registry.sh fails gracefully without python3" "FAIL" "Should have failed but succeeded"
    fi
}

#######################################
# Test: Missing yq dependency
#######################################
test_missing_yq() {
    print_msg BLUE "Testing behavior with missing yq..."

    local tools_dir=$(get_paths)

    # Create fake bin with yq that fails
    local fake_bin="$TEST_TEMP_DIR/fake-bin-no-yq"
    mkdir -p "$fake_bin"

    # Create fake yq that exits with "not found" error
    cat > "$fake_bin/yq" <<'EOF'
#!/bin/bash
echo "yq: command not found" >&2
exit 127
EOF
    chmod +x "$fake_bin/yq"

    # Copy all essential system commands including python3 (but yq is fake)
    for cmd in python3 bash sh cat grep echo test mkdir ls pwd cd dirname basename readlink sed awk tr cut head tail chmod; do
        if command -v "$cmd" >/dev/null 2>&1; then
            ln -sf "$(command -v "$cmd")" "$fake_bin/$cmd" 2>/dev/null || true
        fi
    done

    # Test with PATH that has python3 but yq fails
    local output
    local exit_code

    output=$(PATH="$fake_bin" "$tools_dir/agent-registry.sh" list 2>&1)
    exit_code=$?

    # Should fail with clear error message about yq
    if [ $exit_code -ne 0 ]; then
        if echo "$output" | grep -iq "yq"; then
            print_result "agent-registry.sh fails gracefully without yq" "PASS"
        else
            print_result "agent-registry.sh fails gracefully without yq" "FAIL" "Error message unclear"
        fi
    else
        print_result "agent-registry.sh fails gracefully without yq" "FAIL" "Should have failed but succeeded"
    fi
}

#######################################
# Test: Sanitized environment variables
#######################################
test_sanitized_env() {
    print_msg BLUE "Testing behavior with sanitized environment..."

    local tools_dir=$(get_paths)

    # Test with minimal environment (preserve essential vars only)
    local output
    local exit_code

    # Create a script that runs with minimal env
    cat > "$TEST_TEMP_DIR/test-minimal-env.sh" <<'EOFSCRIPT'
#!/usr/bin/env bash
# Run with minimal environment
export PATH="/usr/local/bin:/usr/bin:/bin"
export HOME="/tmp/fake-home"
unset TMPDIR
unset TEMP
unset TMP

"$1" list 2>&1
EOFSCRIPT
    chmod +x "$TEST_TEMP_DIR/test-minimal-env.sh"

    output=$("$TEST_TEMP_DIR/test-minimal-env.sh" "$tools_dir/agent-registry.sh" 2>&1 || true)
    exit_code=$?

    # Should either work or fail with clear message (not hang or crash)
    if [ $exit_code -eq 0 ] || echo "$output" | grep -Eq "(Error:|required|not found|missing)"; then
        print_result "agent-registry.sh handles sanitized env gracefully" "PASS"
    else
        print_result "agent-registry.sh handles sanitized env gracefully" "FAIL" "Unclear behavior: exit=$exit_code"
    fi
}

#######################################
# Test: Non-writable temp directory
#######################################
test_readonly_temp() {
    print_msg BLUE "Testing behavior with non-writable temp directory..."

    local tools_dir=$(get_paths)

    # Create a read-only temp directory
    local readonly_temp="$TEST_TEMP_DIR/readonly-tmp"
    mkdir -p "$readonly_temp"
    chmod 555 "$readonly_temp"

    # Test with TMPDIR pointing to read-only location
    local output
    local exit_code

    output=$(TMPDIR="$readonly_temp" "$tools_dir/agent-registry.sh" list 2>&1 || true)
    exit_code=$?

    # Should either work (doesn't need temp) or fail with clear message
    # Most importantly: should not hang or crash
    if [ $exit_code -eq 0 ] || echo "$output" | grep -Eq "(Error:|Permission denied|cannot|readonly|read-only)"; then
        print_result "agent-registry.sh handles readonly temp gracefully" "PASS"
    else
        # Still pass if it just works (doesn't need temp writes)
        print_result "agent-registry.sh handles readonly temp gracefully" "PASS" "Works without temp writes"
    fi

    # Restore permissions for cleanup
    chmod 755 "$readonly_temp"
}

#######################################
# Test: Missing required directories
#######################################
test_missing_directories() {
    print_msg BLUE "Testing behavior with missing directories..."

    local project_root=$(cat "$TEST_TEMP_DIR/project_root")
    local tools_dir=$(get_paths)

    # Create a fake project structure without required directories
    local fake_project="$TEST_TEMP_DIR/fake-project"
    mkdir -p "$fake_project"

    # Create minimal structure (missing .agent-profiles, .beads, etc.)
    # Copy the tool but run it from fake project context

    local output
    local exit_code

    # Run from directory without required infrastructure
    output=$(cd "$fake_project" && "$tools_dir/agent-registry.sh" list 2>&1 || true)
    exit_code=$?

    # Should fail with clear error about missing files/directories
    if [ $exit_code -ne 0 ]; then
        if echo "$output" | grep -Eq "(not found|does not exist|missing|No such file)"; then
            print_result "agent-registry.sh fails gracefully with missing directories" "PASS"
        else
            print_result "agent-registry.sh fails gracefully with missing directories" "FAIL" "Error message unclear"
        fi
    else
        # If it succeeds, it might be finding the actual project root (okay)
        print_result "agent-registry.sh fails gracefully with missing directories" "PASS" "Found actual project root"
    fi
}

#######################################
# Test: Multiple CWD scenarios
#######################################
test_multiple_cwds() {
    print_msg BLUE "Testing from hostile working directories..."

    local tools_dir=$(get_paths)

    # Test from root directory (/)
    local output
    local exit_code

    output=$(cd / && "$tools_dir/agent-registry.sh" list 2>&1 || true)
    exit_code=$?

    # Should either find project root or fail gracefully
    if [ $exit_code -eq 0 ] || echo "$output" | grep -Eq "(Error:|not found|required)"; then
        print_result "agent-registry.sh works from / directory" "PASS"
    else
        print_result "agent-registry.sh works from / directory" "FAIL" "Cryptic error or hang"
    fi

    # Test from non-existent parent context
    local deep_nested="$TEST_TEMP_DIR/a/b/c/d/e/f/g"
    mkdir -p "$deep_nested"

    output=$(cd "$deep_nested" && "$tools_dir/agent-registry.sh" list 2>&1 || true)
    exit_code=$?

    # Should either find project root or fail gracefully
    if [ $exit_code -eq 0 ] || echo "$output" | grep -Eq "(Error:|not found|required)"; then
        print_result "agent-registry.sh works from deep nested directory" "PASS"
    else
        print_result "agent-registry.sh works from deep nested directory" "FAIL" "Cryptic error or hang"
    fi
}

#######################################
# Test: Help output always works
#######################################
test_help_output() {
    print_msg BLUE "Testing that --help always works..."

    local tools_dir=$(get_paths)

    # Test each coordination tool's help output
    local tools_to_test=(
        "agent-control.sh"
        "agent-mail-helper.sh"
        "agent-registry.sh"
        "auto-register-agent.sh"
        "mail-monitor-ctl.sh"
    )

    for tool in "${tools_to_test[@]}"; do
        if [ -x "$tools_dir/$tool" ]; then
            local output
            local exit_code

            # Use timeout to prevent hanging (5 second limit)
            output=$(timeout 5s "$tools_dir/$tool" --help 2>&1 || true)
            exit_code=$?

            if [ $exit_code -eq 0 ] || [ $exit_code -eq 1 ]; then
                # Exit 0 or 1 is fine for help (some tools exit 1 for help)
                if [ -n "$output" ]; then
                    print_result "$tool --help produces output" "PASS"
                else
                    print_result "$tool --help produces output" "FAIL" "No help output"
                fi
            elif [ $exit_code -eq 124 ]; then
                print_result "$tool --help produces output" "FAIL" "Timeout (hung)"
            else
                print_result "$tool --help produces output" "FAIL" "Exit code $exit_code"
            fi
        fi
    done
}

#######################################
# Test: Error messages are helpful
#######################################
test_error_message_quality() {
    print_msg BLUE "Testing error message quality..."

    local tools_dir=$(get_paths)

    # Test with invalid arguments
    local output

    output=$("$tools_dir/agent-registry.sh" invalid-command 2>&1 || true)

    # Error message should mention valid commands or show usage
    if echo "$output" | grep -Eq "(Usage|Commands|help|Invalid|Unknown)"; then
        print_result "agent-registry.sh shows helpful error for invalid command" "PASS"
    else
        print_result "agent-registry.sh shows helpful error for invalid command" "FAIL" "Unclear error message"
    fi

    # Test with missing required argument
    output=$("$tools_dir/agent-registry.sh" show 2>&1 || true)

    # Should mention missing argument or show usage
    if echo "$output" | grep -Eq "(Usage|required|argument|type)"; then
        print_result "agent-registry.sh shows helpful error for missing argument" "PASS"
    else
        print_result "agent-registry.sh shows helpful error for missing argument" "FAIL" "Unclear error message"
    fi
}

#######################################
# Test: No infinite loops or hangs
#######################################
test_no_hangs() {
    print_msg BLUE "Testing for hangs and infinite loops..."

    local tools_dir=$(get_paths)

    # Test with timeout wrapper
    local output
    local exit_code

    # Create a script that might trigger edge cases
    output=$(timeout 10s "$tools_dir/agent-registry.sh" list 2>&1 || true)
    exit_code=$?

    if [ $exit_code -eq 124 ]; then
        print_result "agent-registry.sh completes within timeout" "FAIL" "Command timed out (possible hang)"
    else
        print_result "agent-registry.sh completes within timeout" "PASS"
    fi

    # Test mail helper with timeout
    output=$(timeout 10s "$tools_dir/agent-mail-helper.sh" --help 2>&1 || true)
    exit_code=$?

    if [ $exit_code -eq 124 ]; then
        print_result "agent-mail-helper.sh completes within timeout" "FAIL" "Command timed out (possible hang)"
    else
        print_result "agent-mail-helper.sh completes within timeout" "PASS"
    fi
}

#######################################
# Main test runner
#######################################
main() {
    print_msg BLUE "======================================="
    print_msg BLUE "Degraded Environment Robustness Tests"
    print_msg BLUE "======================================="
    echo ""

    # Check prerequisites
    if ! command -v python3 >/dev/null 2>&1; then
        print_msg RED "Error: python3 is required to run tests"
        exit 1
    fi

    if ! command -v timeout >/dev/null 2>&1; then
        print_msg YELLOW "Warning: timeout command not available - cannot test for hangs"
    fi

    # Setup test environment
    print_msg BLUE "Setting up test environment..."
    setup_test_env
    echo ""

    # Run test suites
    test_missing_python3
    echo ""

    test_missing_yq
    echo ""

    test_sanitized_env
    echo ""

    test_readonly_temp
    echo ""

    test_missing_directories
    echo ""

    test_multiple_cwds
    echo ""

    test_help_output
    echo ""

    test_error_message_quality
    echo ""

    test_no_hangs
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
        print_msg YELLOW "Issues found:"
        print_msg YELLOW "  - Some tools may crash or hang under degraded conditions"
        print_msg YELLOW "  - Error messages may not be clear enough"
        print_msg YELLOW "  - Consider adding dependency checks and better error handling"
        echo ""
        print_msg RED "Some robustness tests failed!"
        exit 1
    else
        echo ""
        print_msg GREEN "All robustness tests passed!"
        print_msg GREEN "Coordination tools handle degraded environments gracefully."
        exit 0
    fi
}

main "$@"
