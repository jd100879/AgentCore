#!/bin/bash
# Comprehensive test suite for idle-agent notifications
# Tests edge cases and real-world scenarios

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test state
TESTS_PASSED=0
TESTS_FAILED=0
TEST_LOG="$PROJECT_DIR/tmp/idle-notification-test.log"

# Ensure tmp directory exists
mkdir -p "$PROJECT_DIR/tmp"

# Helper: Print test header
test_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}TEST: $1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
    echo "[TEST] $1" >> "$TEST_LOG"
}

# Helper: Print test result
test_result() {
    local test_name="$1"
    local result="$2"  # PASS or FAIL
    local message="$3"

    if [ "$result" = "PASS" ]; then
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        echo "  $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "[PASS] $test_name: $message" >> "$TEST_LOG"
    else
        echo -e "${RED}✗ FAIL${NC}: $test_name"
        echo "  $message"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "[FAIL] $test_name: $message" >> "$TEST_LOG"
    fi
}

# Helper: Create test bead
create_test_bead() {
    local title="$1"
    local status="${2:-open}"

    br create --title "$title" --status "$status" --priority P3 --description "Test bead for idle-agent notification testing" --json 2>/dev/null | jq -r 'if type == "array" then .[0].id else .id end' 2>/dev/null || echo ""
}

# Helper: Delete test bead
delete_test_bead() {
    local bead_id="$1"
    br close "$bead_id" >/dev/null 2>&1 || true
}

# Helper: Create fake agent tracking file
create_agent_tracking() {
    local agent_name="$1"
    local bead_id="$2"
    echo "$bead_id" > "/tmp/agent-bead-${agent_name}.txt"
}

# Helper: Remove agent tracking file
remove_agent_tracking() {
    local agent_name="$1"
    mv "/tmp/agent-bead-${agent_name}.txt" "$PROJECT_DIR/review-for-delete/" 2>/dev/null || true
}

# Helper: Count notifications sent to agent (from activity log)
count_notifications() {
    local agent="$1"
    local since="${2:-0}"  # Unix timestamp to count from

    grep "idle_notification_sent" "$PROJECT_DIR/.beads/agent-activity.jsonl" 2>/dev/null | \
        jq -r --arg ag "$agent" --arg since "$since" \
        'select(.agent == $ag) | select(.action == "idle_notification_sent") |
         select((.timestamp | fromdateiso8601) >= ($since | tonumber)) |
         .timestamp' | wc -l | tr -d ' '
}

# Helper: Clear agent inbox
clear_inbox() {
    local agent="$1"
    # Mark all as read
    "$SCRIPT_DIR/agent-mail-helper.sh" list --unread-only 2>/dev/null | while read -r msg_id; do
        "$SCRIPT_DIR/agent-mail-helper.sh" mark-read "$msg_id" 2>/dev/null || true
    done
}

# Helper: Clear recent idle notifications from activity log (for testing)
clear_test_idle_notifications() {
    # Remove idle_notification_sent entries from last 10 minutes
    # This allows tests to run without hitting cooldown
    local temp_log="$PROJECT_DIR/.beads/agent-activity.jsonl.test-backup"
    local cutoff_time=$(date -u -v-10M +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "10 minutes ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)

    # Filter out recent idle_notification_sent entries
    jq -c --arg cutoff "$cutoff_time" \
        'select(.action != "idle_notification_sent" or .timestamp < $cutoff)' \
        "$PROJECT_DIR/.beads/agent-activity.jsonl" > "$temp_log" 2>/dev/null || true

    # Replace original with filtered version
    if [ -f "$temp_log" ] && [ -s "$temp_log" ]; then
        cat "$temp_log" > "$PROJECT_DIR/.beads/agent-activity.jsonl"
        rm -f "$temp_log"
    fi
}

# Setup: Clear test log
setup_tests() {
    echo "========================================" > "$TEST_LOG"
    echo "Idle-Agent Notification Test Suite" >> "$TEST_LOG"
    echo "Started: $(date)" >> "$TEST_LOG"
    echo "========================================" >> "$TEST_LOG"

    echo -e "${YELLOW}Setting up test environment...${NC}"

    # Ensure bead-stale-monitor is running
    if ! "$SCRIPT_DIR/bead-stale-monitor.sh" status >/dev/null 2>&1; then
        echo -e "${YELLOW}Starting bead-stale-monitor...${NC}"
        "$SCRIPT_DIR/bead-stale-monitor.sh" start --interval 10
        sleep 2
    fi
}

# Cleanup: Remove test artifacts
cleanup_tests() {
    echo -e "\n${YELLOW}Cleaning up test artifacts...${NC}"

    # Remove test beads
    br list --json 2>/dev/null | jq -r '.[] | select(.title | startswith("TEST:")) | .id' | while read -r bead_id; do
        delete_test_bead "$bead_id"
    done
}

# Test 1: No notifications when all agents busy
test_all_agents_busy() {
    test_header "Test 1: All agents busy - no notifications"

    # Get active agents from agentcore session only
    local agents=$(tmux list-panes -t agentcore -F "#{@agent_name}" 2>/dev/null | grep -v '^$' | sort -u | head -3)

    if [ -z "$agents" ]; then
        test_result "All agents busy" "SKIP" "No active agents found"
        return
    fi

    # Create tracking files for all agents (make them busy)
    local test_bead=$(create_test_bead "TEST: Busy agent test")

    while IFS= read -r agent; do
        create_agent_tracking "$agent" "$test_bead"
    done <<< "$agents"

    # Create an open bead
    local open_bead=$(create_test_bead "TEST: Available work")

    # Get timestamp before test
    local test_start=$(date +%s)

    # Run monitor check
    "$SCRIPT_DIR/bead-stale-monitor.sh" check
    sleep 2

    # Count notifications sent since test started (should be 0)
    local notification_count=0
    while IFS= read -r agent; do
        local agent_notifications=$(count_notifications "$agent" "$test_start")
        notification_count=$((notification_count + agent_notifications))
    done <<< "$agents"

    # Cleanup
    delete_test_bead "$open_bead"
    delete_test_bead "$test_bead"
    while IFS= read -r agent; do
        remove_agent_tracking "$agent"
    done <<< "$agents"

    if [ "$notification_count" -eq 0 ]; then
        test_result "All agents busy" "PASS" "No notifications sent when all agents busy"
    else
        test_result "All agents busy" "FAIL" "Expected 0 notifications, got $notification_count"
    fi
}

# Test 2: Notification sent when agent idle and beads available
test_idle_agent_with_beads() {
    test_header "Test 2: Idle agent with available beads - notification sent"

    # Clear previous idle notifications to avoid cooldown
    clear_test_idle_notifications

    # Get one active agent from agentcore session
    local agent=$(tmux list-panes -t agentcore -F "#{@agent_name}" 2>/dev/null | grep -v '^$' | head -1)

    if [ -z "$agent" ]; then
        test_result "Idle agent notification" "SKIP" "No active agents found"
        return
    fi

    # Make agent idle (remove tracking file if exists)
    remove_agent_tracking "$agent"

    # Create open bead
    local open_bead=$(create_test_bead "TEST: Available work for idle agent")

    # Get timestamp before test
    local test_start=$(date +%s)

    # Run monitor check
    "$SCRIPT_DIR/bead-stale-monitor.sh" check
    sleep 2

    # Check if notification was sent
    local notification_sent=$(count_notifications "$agent" "$test_start")

    # Cleanup
    delete_test_bead "$open_bead"

    if [ "$notification_sent" -ge 1 ]; then
        test_result "Idle agent notification" "PASS" "Notification sent to idle agent $agent"
    else
        test_result "Idle agent notification" "FAIL" "No notification sent to idle agent $agent"
    fi
}

# Test 3: No notifications when no beads available
test_idle_agent_no_beads() {
    test_header "Test 3: Idle agent with no beads - no notification"

    # Get one active agent from agentcore session
    local agent=$(tmux list-panes -t agentcore -F "#{@agent_name}" 2>/dev/null | grep -v '^$' | head -1)

    if [ -z "$agent" ]; then
        test_result "No beads available" "SKIP" "No active agents found"
        return
    fi

    # Make agent idle
    remove_agent_tracking "$agent"

    # Temporarily close all open beads for this test
    local open_beads=$(br list --status open --json 2>/dev/null | jq -r '.[].id')
    local closed_beads=()

    while IFS= read -r bead_id; do
        [ -z "$bead_id" ] && continue
        br close "$bead_id" >/dev/null 2>&1 || true
        closed_beads+=("$bead_id")
    done <<< "$open_beads"

    # Get timestamp before test
    local test_start=$(date +%s)

    # Run monitor check
    "$SCRIPT_DIR/bead-stale-monitor.sh" check
    sleep 2

    # Check that no notifications were sent
    local notification_sent=$(count_notifications "$agent" "$test_start")

    # Re-open the beads we closed
    for bead_id in "${closed_beads[@]}"; do
        br update "$bead_id" --status open >/dev/null 2>&1 || true
    done

    if [ "$notification_sent" -eq 0 ]; then
        test_result "No beads available" "PASS" "No notification sent when no beads available"
    else
        test_result "No beads available" "FAIL" "Unexpected notification sent"
    fi
}

# Test 4: Multiple idle agents all notified
test_multiple_idle_agents() {
    test_header "Test 4: Multiple idle agents - all notified"

    # Clear previous idle notifications to avoid cooldown
    clear_test_idle_notifications

    # Get multiple active agents from agentcore session
    local agents=$(tmux list-panes -t agentcore -F "#{@agent_name}" 2>/dev/null | grep -v '^$' | sort -u | head -3)
    local agent_count=$(echo "$agents" | wc -l | tr -d ' ')

    if [ "$agent_count" -lt 2 ]; then
        test_result "Multiple idle agents" "SKIP" "Need at least 2 agents, found $agent_count"
        return
    fi

    # Make all agents idle
    while IFS= read -r agent; do
        remove_agent_tracking "$agent"
    done <<< "$agents"

    # Create open bead
    local open_bead=$(create_test_bead "TEST: Work for multiple agents")

    # Get timestamp before test
    local test_start=$(date +%s)

    # Run monitor check
    "$SCRIPT_DIR/bead-stale-monitor.sh" check
    sleep 2

    # Count notifications for all agents
    local notifications_sent=0
    while IFS= read -r agent; do
        local agent_notifications=$(count_notifications "$agent" "$test_start")
        notifications_sent=$((notifications_sent + agent_notifications))
    done <<< "$agents"

    # Cleanup
    delete_test_bead "$open_bead"

    if [ "$notifications_sent" -eq "$agent_count" ]; then
        test_result "Multiple idle agents" "PASS" "All $agent_count idle agents notified"
    else
        test_result "Multiple idle agents" "FAIL" "Expected $agent_count notifications, got $notifications_sent"
    fi
}

# Test 5: Spam prevention (cooldown period)
test_spam_prevention() {
    test_header "Test 5: Spam prevention - cooldown period"

    # Clear previous idle notifications to avoid cooldown
    clear_test_idle_notifications

    # Get one active agent from agentcore session
    local agent=$(tmux list-panes -t agentcore -F "#{@agent_name}" 2>/dev/null | grep -v '^$' | head -1)

    if [ -z "$agent" ]; then
        test_result "Spam prevention" "SKIP" "No active agents found"
        return
    fi

    # Make agent idle
    remove_agent_tracking "$agent"

    # Create open bead
    local open_bead=$(create_test_bead "TEST: Spam prevention test")

    # Get timestamp before test
    local test_start=$(date +%s)

    # First notification
    "$SCRIPT_DIR/bead-stale-monitor.sh" check
    sleep 2
    local first_notification=$(count_notifications "$agent" "$test_start")

    # Immediate second check (should be blocked by cooldown)
    "$SCRIPT_DIR/bead-stale-monitor.sh" check
    sleep 2
    local total_notifications=$(count_notifications "$agent" "$test_start")

    # Cleanup
    delete_test_bead "$open_bead"

    if [ "$first_notification" -eq 1 ] && [ "$total_notifications" -eq 1 ]; then
        test_result "Spam prevention" "PASS" "Cooldown prevented duplicate notification"
    else
        test_result "Spam prevention" "FAIL" "Expected 1 notification total, got $total_notifications"
    fi
}

# Test 6: Agent claims bead after notification
test_agent_claims_bead() {
    test_header "Test 6: Agent claims bead after notification"

    # Clear previous idle notifications to avoid cooldown
    clear_test_idle_notifications

    # Get one active agent from agentcore session
    local agent=$(tmux list-panes -t agentcore -F "#{@agent_name}" 2>/dev/null | grep -v '^$' | head -1)

    if [ -z "$agent" ]; then
        test_result "Agent claims bead" "SKIP" "No active agents found"
        return
    fi

    # Make agent idle
    remove_agent_tracking "$agent"

    # Create open bead
    local open_bead=$(create_test_bead "TEST: Agent will claim this")

    # Get timestamp before test
    local test_start=$(date +%s)

    # First check - agent is idle, notification sent
    "$SCRIPT_DIR/bead-stale-monitor.sh" check
    sleep 2
    local notification_sent=$(count_notifications "$agent" "$test_start")

    # Simulate agent claiming bead
    create_agent_tracking "$agent" "$open_bead"

    # Second check - agent is now busy, no notification
    local second_check_start=$(date +%s)
    "$SCRIPT_DIR/bead-stale-monitor.sh" check 2>&1 | tee /tmp/test-agent-busy.log >&2
    sleep 2
    local second_notification=$(count_notifications "$agent" "$second_check_start")
    local busy_message=$(grep -c "Agent $agent is busy" /tmp/test-agent-busy.log 2>/dev/null || echo "0")

    # Cleanup
    delete_test_bead "$open_bead"
    remove_agent_tracking "$agent"

    if [ "$notification_sent" -eq 1 ] && [ "$second_notification" -eq 0 ] && [ "$busy_message" -ge 1 ]; then
        test_result "Agent claims bead" "PASS" "Agent detected as busy after claiming bead"
    else
        test_result "Agent claims bead" "FAIL" "Expected notification=1, then busy detection. Got: notification=$notification_sent, second=$second_notification, busy=$busy_message"
    fi
}

# Test 7: Stale tracking files don't cause false busy state
test_stale_tracking_files() {
    test_header "Test 7: Stale/invalid tracking files"

    # Clear previous idle notifications to avoid cooldown
    clear_test_idle_notifications

    # Get one active agent from agentcore session
    local agent=$(tmux list-panes -t agentcore -F "#{@agent_name}" 2>/dev/null | grep -v '^$' | head -1)

    if [ -z "$agent" ]; then
        test_result "Stale tracking" "SKIP" "No active agents found"
        return
    fi

    # Create empty tracking file
    echo "" > "/tmp/agent-bead-${agent}.txt"

    # Create open bead
    local open_bead=$(create_test_bead "TEST: Stale tracking test")

    # Get timestamp before test
    local test_start=$(date +%s)

    # Run check - empty tracking file should be treated as idle
    "$SCRIPT_DIR/bead-stale-monitor.sh" check
    sleep 2
    local notification_sent=$(count_notifications "$agent" "$test_start")

    # Cleanup
    delete_test_bead "$open_bead"
    remove_agent_tracking "$agent"

    if [ "$notification_sent" -eq 1 ]; then
        test_result "Stale tracking" "PASS" "Empty tracking file treated as idle"
    else
        test_result "Stale tracking" "FAIL" "Agent with empty tracking file not notified"
    fi
}

# Test 8: Real-world integration test
test_real_world_integration() {
    test_header "Test 8: Real-world integration test"

    echo "This test runs the actual monitor and verifies behavior with real agents"

    # Get current state from agentcore session only
    local active_agents=$(tmux list-panes -t agentcore -F "#{@agent_name}" 2>/dev/null | grep -v '^$' | wc -l | tr -d ' ')
    local idle_agents=$(
        tmux list-panes -t agentcore -F "#{@agent_name}" 2>/dev/null | grep -v '^$' | while read agent; do
            if [ ! -f "/tmp/agent-bead-${agent}.txt" ] || [ ! -s "/tmp/agent-bead-${agent}.txt" ]; then
                echo "$agent"
            fi
        done | wc -l | tr -d ' '
    )
    local open_beads=$(br list --status open --json 2>/dev/null | jq 'length')

    echo "  Active agents: $active_agents"
    echo "  Idle agents: $idle_agents"
    echo "  Open beads: $open_beads"

    # Get timestamp before test
    local test_start=$(date +%s)

    # Run actual monitor check
    "$SCRIPT_DIR/bead-stale-monitor.sh" check 2>&1 | tee /tmp/test-real-world.log >&2
    sleep 2

    # Check results - count all idle notifications since test started
    local notifications=$(grep "idle_notification_sent" "$PROJECT_DIR/.beads/agent-activity.jsonl" 2>/dev/null | \
        jq -r --arg since "$test_start" \
        'select(.action == "idle_notification_sent") |
         select((.timestamp | fromdateiso8601) >= ($since | tonumber)) |
         .agent' | wc -l | tr -d ' ')
    local busy_detections=$(grep -c "is busy" /tmp/test-real-world.log 2>/dev/null || echo "0")

    echo "  Notifications sent: $notifications"
    echo "  Busy agents detected: $busy_detections"

    # Validation
    local expected_notifications=0
    if [ "$open_beads" -gt 0 ] && [ "$idle_agents" -gt 0 ]; then
        expected_notifications="$idle_agents"
    fi

    if [ "$notifications" -le "$expected_notifications" ]; then
        test_result "Real-world integration" "PASS" "Monitor behavior matches expectations"
    else
        test_result "Real-world integration" "FAIL" "Unexpected notification count: $notifications (expected <= $expected_notifications)"
    fi
}

# Main test execution
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Idle-Agent Notification Test Suite${NC}"
    echo -e "${BLUE}========================================${NC}\n"

    setup_tests

    # Run all tests
    test_all_agents_busy
    test_idle_agent_with_beads
    test_idle_agent_no_beads
    test_multiple_idle_agents
    test_spam_prevention
    test_agent_claims_bead
    test_stale_tracking_files
    test_real_world_integration

    cleanup_tests

    # Print summary
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}Test Summary${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    echo -e "\nDetailed log: $TEST_LOG\n"

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed!${NC}\n"
        exit 0
    else
        echo -e "${RED}✗ Some tests failed${NC}\n"
        exit 1
    fi
}

# Run tests
main "$@"
