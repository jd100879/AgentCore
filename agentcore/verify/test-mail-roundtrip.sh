#!/usr/bin/env bash
# test-mail-roundtrip.sh - End-to-end mail roundtrip integration test
#
# Tests real agent-to-agent communication flow via canonical paths
# to catch integration breaks that unit tests miss.
#
# Uses real registered agents from the system.
#
# Part of: Phase 2 Integration Testing (bd-217)

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
TEST_TEMP_DIR=""
SENDER_AGENT=""
RECEIVER_AGENT=""

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
    # Clean up temp directory only (real agents stay registered)
    if [ -n "$TEST_TEMP_DIR" ] && [ -d "$TEST_TEMP_DIR" ]; then
        rm -rf "$TEST_TEMP_DIR"
        print_msg YELLOW "  Cleaned up temp directory"
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

    # Find agents with active pane identity files
    local agent_array=()
    for identity_file in "$project_root/panes/"*.identity; do
        [ -f "$identity_file" ] || continue
        local mail_name=$(jq -r '.agent_mail_name // empty' "$identity_file" 2>/dev/null)
        if [ -n "$mail_name" ]; then
            # Verify this agent is also registered in mail system
            local mail_script=$(get_mail_helper_script "$project_root")
            if "$mail_script" list 2>/dev/null | grep -q "^$mail_name"; then
                agent_array+=("$mail_name")
            fi
        fi
    done

    # Remove duplicates
    local unique_agents=()
    local seen=""
    for agent in "${agent_array[@]}"; do
        if [[ " $seen " != *" $agent "* ]]; then
            unique_agents+=("$agent")
            seen="$seen $agent "
        fi
    done

    if [ ${#unique_agents[@]} -lt 2 ]; then
        print_msg RED "Error: Need at least 2 agents with active panes, found ${#unique_agents[@]}"
        if [ ${#unique_agents[@]} -gt 0 ]; then
            print_msg YELLOW "Available agents with panes:"
            printf "  - %s\n" "${unique_agents[@]}"
        fi
        print_msg YELLOW "Please start at least 2 agent sessions before running this test"
        exit 1
    fi

    # Use first two agents
    SENDER_AGENT="${unique_agents[0]}"
    RECEIVER_AGENT="${unique_agents[1]}"

    print_msg GREEN "  Created temp directory: $TEST_TEMP_DIR"
    print_msg GREEN "  Sender Agent: $SENDER_AGENT"
    print_msg GREEN "  Receiver Agent: $RECEIVER_AGENT"
}

#######################################
# Get canonical mail helper script path
#######################################
get_mail_helper_script() {
    local project_root="$1"

    # Prefer canonical agentcore/tools path if it exists
    if [ -x "$project_root/agentcore/tools/agent-mail-helper.sh" ]; then
        echo "$project_root/agentcore/tools/agent-mail-helper.sh"
    elif [ -x "$project_root/scripts/agent-mail-helper.sh" ]; then
        echo "$project_root/scripts/agent-mail-helper.sh"
    else
        print_msg RED "Error: agent-mail-helper.sh not found"
        exit 1
    fi
}

#######################################
# Send message from agent via canonical path
#######################################
test_send_message_from_cwd() {
    local test_name="$1"
    local test_cwd="$2"
    local from_agent="$3"
    local to_agent="$4"
    local subject="$5"
    local body="$6"

    local project_root=$(cat "$TEST_TEMP_DIR/project_root")
    local mail_script=$(get_mail_helper_script "$project_root")

    # Find the sender agent's pane identity file
    local sender_identity=""
    for identity_file in "$project_root/panes/"*.identity; do
        [ -f "$identity_file" ] || continue
        local mail_name=$(jq -r '.agent_mail_name // empty' "$identity_file" 2>/dev/null)
        if [ "$mail_name" = "$from_agent" ]; then
            sender_identity="$identity_file"
            break
        fi
    done

    if [ -z "$sender_identity" ]; then
        print_result "$test_name" "FAIL"
        echo "  Error: Could not find identity file for agent $from_agent" >&2
        return 1
    fi

    # Get pane ID from identity
    local pane_id=$(jq -r '.pane // empty' "$sender_identity" 2>/dev/null)
    local safe_pane=$(echo "$pane_id" | tr ':.' '-')

    # Run from specified CWD using canonical path with sender's pane context
    local output
    if output=$(cd "$test_cwd" && \
                TMUX_PANE="$pane_id" \
                MAIL_SENDER_NAME="$from_agent" \
                "$mail_script" send "$to_agent" "$subject" "$body" 2>&1); then
        print_result "$test_name" "PASS"
        return 0
    else
        print_result "$test_name" "FAIL"
        echo "  Output: $output" | head -5 >&2
        return 1
    fi
}

#######################################
# Check inbox for agent via canonical path
#######################################
test_check_inbox_from_cwd() {
    local test_name="$1"
    local test_cwd="$2"
    local agent_name="$3"
    local expected_subject="$4"

    local project_root=$(cat "$TEST_TEMP_DIR/project_root")
    local mail_script=$(get_mail_helper_script "$project_root")

    # Find the agent's pane identity file
    local agent_identity=""
    for identity_file in "$project_root/panes/"*.identity; do
        [ -f "$identity_file" ] || continue
        local mail_name=$(jq -r '.agent_mail_name // empty' "$identity_file" 2>/dev/null)
        if [ "$mail_name" = "$agent_name" ]; then
            agent_identity="$identity_file"
            break
        fi
    done

    if [ -z "$agent_identity" ]; then
        print_result "$test_name" "FAIL"
        echo "  Error: Could not find identity file for agent $agent_name" >&2
        return 1
    fi

    # Get pane ID from identity
    local pane_id=$(jq -r '.pane // empty' "$agent_identity" 2>/dev/null)

    # Run from specified CWD using canonical path with agent's pane context
    local output
    if output=$(cd "$test_cwd" && \
                TMUX_PANE="$pane_id" \
                "$mail_script" inbox 10 2>&1); then
        # Check if expected message is in inbox (use -F for fixed string matching)
        if echo "$output" | grep -F -q "$expected_subject"; then
            print_result "$test_name" "PASS"
            return 0
        else
            print_result "$test_name" "FAIL"
            echo "  Expected subject '$expected_subject' not found in inbox" >&2
            echo "  Output: $output" | head -10 >&2
            return 1
        fi
    else
        print_result "$test_name" "FAIL"
        echo "  Failed to check inbox" >&2
        echo "  Output: $output" | head -5 >&2
        return 1
    fi
}

#######################################
# Test message roundtrip from multiple CWDs
#######################################
test_mail_roundtrip() {
    print_msg BLUE "Testing mail roundtrip from multiple CWDs..."

    local project_root=$(cat "$TEST_TEMP_DIR/project_root")

    print_msg BLUE "  Using agents: $SENDER_AGENT → $RECEIVER_AGENT"

    # Test 1: Send from repo root
    local subject1="[TEST] Message from repo root $(date +%s)"
    test_send_message_from_cwd \
        "send message from repo root" \
        "$project_root" \
        "$SENDER_AGENT" \
        "$RECEIVER_AGENT" \
        "$subject1" \
        "This is a test message sent from repo root"

    # Wait for message delivery
    sleep 1

    # Test 2: Check inbox from /tmp
    test_check_inbox_from_cwd \
        "check inbox from /tmp" \
        "/tmp" \
        "$RECEIVER_AGENT" \
        "$subject1"

    # Test 3: Send from /tmp
    local subject2="[TEST] Message from /tmp $(date +%s)"
    test_send_message_from_cwd \
        "send message from /tmp" \
        "/tmp" \
        "$SENDER_AGENT" \
        "$RECEIVER_AGENT" \
        "$subject2" \
        "This is a test message sent from /tmp"

    # Wait for message delivery
    sleep 1

    # Test 4: Check inbox from deep nested path
    test_check_inbox_from_cwd \
        "check inbox from deep nested path" \
        "$TEST_TEMP_DIR/deep/nested/path" \
        "$RECEIVER_AGENT" \
        "$subject2"

    # Test 5: Send from deep nested path
    local subject3="[TEST] Message from deep nested path $(date +%s)"
    test_send_message_from_cwd \
        "send message from deep nested path" \
        "$TEST_TEMP_DIR/deep/nested/path" \
        "$SENDER_AGENT" \
        "$RECEIVER_AGENT" \
        "$subject3" \
        "This is a test message sent from a deep nested directory"

    # Wait for message delivery
    sleep 1

    # Test 6: Check inbox from repo root
    test_check_inbox_from_cwd \
        "check inbox from repo root" \
        "$project_root" \
        "$RECEIVER_AGENT" \
        "$subject3"
}

#######################################
# Test dependency checking
#######################################
test_dependency_check() {
    print_msg BLUE "Testing dependencies..."

    # Check if python3 is available (required for path resolution)
    if command -v python3 >/dev/null 2>&1; then
        print_result "python3 dependency available" "PASS"
    else
        print_msg YELLOW "  ! python3 not installed - tests will fail"
        print_result "python3 dependency available" "FAIL"
    fi

    # Check if curl is available (needed for MCP API calls)
    if command -v curl >/dev/null 2>&1; then
        print_result "curl dependency available" "PASS"
    else
        print_msg YELLOW "  ! curl not installed - mail operations will fail"
        print_result "curl dependency available" "FAIL"
    fi

    # Check if jq is available (needed for JSON parsing)
    if command -v jq >/dev/null 2>&1; then
        print_result "jq dependency available" "PASS"
    else
        print_msg YELLOW "  ! jq not installed - mail operations will fail"
        print_msg YELLOW "  Install with: brew install jq"
        print_result "jq dependency available" "FAIL"
    fi
}

#######################################
# Test mail server connectivity
#######################################
test_mail_server_connectivity() {
    print_msg BLUE "Testing mail server connectivity..."

    local mail_server="${MAIL_SERVER:-http://127.0.0.1:8765}"

    # Try to connect to mail server
    if curl -s --connect-timeout 5 "$mail_server/health" >/dev/null 2>&1; then
        print_result "mail server is reachable" "PASS"
    else
        print_msg YELLOW "  ! Mail server not reachable at $mail_server"
        print_msg YELLOW "  Start mail server with: docker-compose up -d"
        print_result "mail server is reachable" "FAIL"
    fi
}

#######################################
# Main test runner
#######################################
main() {
    print_msg BLUE "======================================="
    print_msg BLUE "Mail Roundtrip Integration Tests"
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

    test_mail_server_connectivity
    echo ""

    # Only run mail roundtrip tests if mail server is available
    if curl -s --connect-timeout 5 "${MAIL_SERVER:-http://127.0.0.1:8765}/health" >/dev/null 2>&1; then
        test_mail_roundtrip
        echo ""
    else
        print_msg YELLOW "Skipping mail roundtrip tests (mail server not available)"
        echo ""
    fi

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
