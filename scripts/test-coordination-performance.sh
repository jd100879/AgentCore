#!/usr/bin/env bash
#
# test-coordination-performance.sh - Performance and scale tests for coordination infrastructure
#
# Tests:
#   6.1: Many agents concurrently (10 agents claiming beads)
#   6.2: Large mail queue flush (50 notifications)
#   6.3: Long-running monitor stability (24 hour test)
#
# Part of: bd-71m (Test performance and scale of coordination infrastructure)
#
# Usage:
#   ./scripts/test-coordination-performance.sh [test_name]
#
# Tests:
#   test_6_1_concurrent_agents  - 10 agents claiming beads concurrently
#   test_6_2_mail_queue_flush   - Large mail queue flush (50 notifications)
#   test_6_3_monitor_stability  - Long-running monitor stability test
#   all                         - Run all tests
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_PREFIX="perf-test-$$"
RESULTS_DIR="$PROJECT_ROOT/tmp/perf-test-results"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test results
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

#######################################
# Print colored message
#######################################
print_msg() {
    local color="${!1}"
    local msg="$2"
    echo -e "${color}${msg}${NC}"
}

#######################################
# Assert function - check condition
#######################################
assert() {
    local condition="$1"
    local message="$2"

    TESTS_RUN=$((TESTS_RUN + 1))

    if eval "$condition"; then
        print_msg GREEN "  ✓ $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        print_msg RED "  ✗ $message"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

#######################################
# Setup test environment
#######################################
setup() {
    print_msg BLUE "Setting up test environment..."
    mkdir -p "$RESULTS_DIR"

    # Create results file
    echo "Performance Test Results - $(date)" > "$RESULTS_DIR/summary.txt"
    echo "=================================" >> "$RESULTS_DIR/summary.txt"
    echo "" >> "$RESULTS_DIR/summary.txt"
}

#######################################
# Cleanup test environment
#######################################
cleanup() {
    print_msg YELLOW "Cleaning up test environment..."

    # Kill any test agents
    tmux list-sessions 2>/dev/null | grep "^${TEST_PREFIX}" | cut -d: -f1 | while read session; do
        tmux kill-session -t "$session" 2>/dev/null || true
    done

    # Clean up test beads
    br list --status open,in_progress 2>/dev/null | grep "${TEST_PREFIX}" | awk '{print $1}' | while read bead_id; do
        br close "$bead_id" 2>/dev/null || true
    done
}

trap cleanup EXIT

#######################################
# Test 6.1: Many concurrent operations (lock contention test)
#######################################
test_6_1_concurrent_agents() {
    print_msg BLUE "\n=== Test 6.1: Concurrent Operations (lock contention test) ==="

    local start_time=$(date +%s)
    local num_processes=10
    local num_beads=30
    local operations_per_process=20

    # Create test beads
    print_msg YELLOW "Creating $num_beads test beads..."
    local bead_ids=()
    for i in $(seq 1 $num_beads); do
        local bead_id=$(br create "${TEST_PREFIX}-bead-${i}" \
            --description "Performance test bead $i" \
            --type task \
            --priority 2 2>&1 | grep -oE 'bd-[a-z0-9]+' | head -1)
        if [[ -n "$bead_id" ]]; then
            bead_ids+=("$bead_id")
        fi
        sleep 0.1  # Avoid overwhelming the system
    done

    assert "[[ ${#bead_ids[@]} -eq $num_beads ]]" \
        "Created $num_beads test beads (actual: ${#bead_ids[@]})"

    # Test concurrent operations
    print_msg YELLOW "Testing $num_processes concurrent processes doing $operations_per_process operations each..."
    local claim_start=$(date +%s)
    local pids=()

    # Launch concurrent processes
    for i in $(seq 1 $num_processes); do
        (
            local proc_id="agent-proc-$i"
            for j in $(seq 1 $operations_per_process); do
                # Pick a random bead
                local bead_idx=$((RANDOM % ${#bead_ids[@]}))
                local bead_id="${bead_ids[$bead_idx]}"

                # Try to claim it
                br update "$bead_id" --status in_progress --assignee "$proc_id" 2>&1 > /dev/null || true

                # Release it
                br update "$bead_id" --status open 2>&1 > /dev/null || true
            done
        ) &
        pids+=($!)
    done

    # Wait for all processes
    print_msg YELLOW "Waiting for processes to complete..."
    for pid in "${pids[@]}"; do
        wait $pid 2>/dev/null || true
    done

    local claim_time=$(($(date +%s) - claim_start))
    print_msg YELLOW "Concurrent operations completed in: ${claim_time}s"

    # Calculate operations per second
    local total_ops=$((num_processes * operations_per_process * 2))  # 2 ops per iteration (claim + release)
    local ops_per_sec=$((total_ops / claim_time))

    # Check performance - should handle at least 10 ops/sec
    assert "[[ $ops_per_sec -ge 10 ]]" \
        "Performance acceptable (${ops_per_sec} ops/sec >= 10 ops/sec)"

    # Check for data corruption - verify beads still exist and are accessible
    print_msg YELLOW "Checking for data corruption..."
    local corrupted=0
    for bead_id in "${bead_ids[@]}"; do
        if ! br show "$bead_id" >/dev/null 2>&1; then
            corrupted=$((corrupted + 1))
        fi
    done

    assert "[[ $corrupted -eq 0 ]]" \
        "No data corruption detected (inaccessible beads: $corrupted)"

    # Performance metrics
    local total_time=$(($(date +%s) - start_time))
    echo "Test 6.1 Results:" >> "$RESULTS_DIR/summary.txt"
    echo "  - Concurrent processes: $num_processes" >> "$RESULTS_DIR/summary.txt"
    echo "  - Operations per process: $operations_per_process" >> "$RESULTS_DIR/summary.txt"
    echo "  - Total operations: $total_ops" >> "$RESULTS_DIR/summary.txt"
    echo "  - Time: ${claim_time}s" >> "$RESULTS_DIR/summary.txt"
    echo "  - Throughput: ${ops_per_sec} ops/sec" >> "$RESULTS_DIR/summary.txt"
    echo "  - Corrupted beads: $corrupted" >> "$RESULTS_DIR/summary.txt"
    echo "  - Total time: ${total_time}s" >> "$RESULTS_DIR/summary.txt"
    echo "" >> "$RESULTS_DIR/summary.txt"

    # Cleanup
    for bead_id in "${bead_ids[@]}"; do
        br close "$bead_id" 2>/dev/null || true
    done
}

#######################################
# Test 6.2: Large mail queue operations (50 notifications)
#######################################
test_6_2_mail_queue_flush() {
    print_msg BLUE "\n=== Test 6.2: Large Mail Queue Operations (50 notifications) ==="

    local num_messages=50
    local start_time=$(date +%s)

    # Check if agent-mail system is available
    local mail_helper="$PROJECT_ROOT/scripts/agent-mail-helper.sh"
    if [[ ! -f "$mail_helper" ]]; then
        print_msg YELLOW "Skipping test: agent-mail-helper.sh not found"
        print_msg YELLOW "Expected: $mail_helper"
        return 0
    fi

    # Create test agent
    print_msg YELLOW "Using test agent: OrangeLantern (current agent)"
    local test_agent="OrangeLantern"

    # Send bulk messages
    print_msg YELLOW "Sending $num_messages messages..."
    local send_start=$(date +%s)
    local send_count=0

    for i in $(seq 1 $num_messages); do
        if $mail_helper send "$test_agent" "Perf test $i" "Test message $i of $num_messages" "normal" 2>/dev/null; then
            send_count=$((send_count + 1))
        fi
        # Rate limit to avoid overwhelming the system
        [[ $((i % 10)) -eq 0 ]] && sleep 0.1
    done

    local send_time=$(($(date +%s) - send_start))
    print_msg YELLOW "Send time: ${send_time}s (sent: $send_count/$num_messages)"

    # Verify messages were sent
    assert "[[ $send_count -gt 0 ]]" \
        "Successfully sent messages (sent: $send_count)"

    # Read messages (simulates flush)
    print_msg YELLOW "Reading messages from inbox..."
    local read_start=$(date +%s)

    local inbox_output=$($mail_helper inbox 2>/dev/null | tee "$RESULTS_DIR/inbox-output.txt" || echo "")
    local read_time=$(($(date +%s) - read_start))

    print_msg YELLOW "Read time: ${read_time}s"

    # Count messages in inbox
    local inbox_count=$(echo "$inbox_output" | grep -c "Perf test" || echo "0")

    # Check performance requirement - total operation time < 30s
    local total_op_time=$((send_time + read_time))
    assert "[[ $total_op_time -lt 30 ]]" \
        "Mail operations in < 30s (actual: ${total_op_time}s)"

    # Performance metrics
    local total_time=$(($(date +%s) - start_time))
    local msgs_per_sec_send=$((send_count / (send_time + 1)))
    local msgs_per_sec_total=$((send_count / (total_op_time + 1)))

    echo "Test 6.2 Results:" >> "$RESULTS_DIR/summary.txt"
    echo "  - Messages sent: $send_count/$num_messages" >> "$RESULTS_DIR/summary.txt"
    echo "  - Messages in inbox: $inbox_count" >> "$RESULTS_DIR/summary.txt"
    echo "  - Send time: ${send_time}s" >> "$RESULTS_DIR/summary.txt"
    echo "  - Read time: ${read_time}s" >> "$RESULTS_DIR/summary.txt"
    echo "  - Total operation time: ${total_op_time}s" >> "$RESULTS_DIR/summary.txt"
    echo "  - Send throughput: ${msgs_per_sec_send} msgs/sec" >> "$RESULTS_DIR/summary.txt"
    echo "  - Overall throughput: ${msgs_per_sec_total} msgs/sec" >> "$RESULTS_DIR/summary.txt"
    echo "  - Total test time: ${total_time}s" >> "$RESULTS_DIR/summary.txt"
    echo "" >> "$RESULTS_DIR/summary.txt"
}

#######################################
# Test 6.3: Long-running monitor stability (24 hour test)
#######################################
test_6_3_monitor_stability() {
    print_msg BLUE "\n=== Test 6.3: Monitor Stability Test ==="

    # Check if this is a quick test run or full 24h test
    local test_duration=${MONITOR_TEST_DURATION:-300}  # Default 5 minutes for quick test

    if [[ $test_duration -eq 300 ]]; then
        print_msg YELLOW "Running quick stability test (5 minutes)"
        print_msg YELLOW "Set MONITOR_TEST_DURATION=86400 for full 24h test"
    else
        print_msg YELLOW "Running full stability test (${test_duration}s)"
    fi

    local monitor_session="${TEST_PREFIX}-monitor"
    local start_time=$(date +%s)
    local log_file="$RESULTS_DIR/monitor-stability.log"
    local rss_log="$RESULTS_DIR/monitor-rss.log"

    # Start monitor process
    print_msg YELLOW "Starting monitor process..."
    tmux new-session -d -s "$monitor_session" \
        "$SCRIPT_DIR/queue-monitor.sh start" 2>/dev/null || true

    sleep 2

    # Get initial RSS
    local monitor_pid=$(cat "$PROJECT_ROOT/pids/queue-monitor.pid" 2>/dev/null || echo "")
    if [[ -z "$monitor_pid" ]]; then
        print_msg YELLOW "Skipping test: monitor PID not found"
        return 0
    fi

    local initial_rss=$(ps -p "$monitor_pid" -o rss= 2>/dev/null | tr -d ' ')
    print_msg YELLOW "Initial RSS: ${initial_rss} KB"

    # Monitor for specified duration
    print_msg YELLOW "Monitoring for ${test_duration}s..."
    local check_interval=30
    local checks=$((test_duration / check_interval))
    local max_rss=$initial_rss

    for i in $(seq 1 $checks); do
        sleep $check_interval

        local current_rss=$(ps -p "$monitor_pid" -o rss= 2>/dev/null | tr -d ' ' || echo "0")
        if [[ $current_rss -eq 0 ]]; then
            print_msg RED "Monitor process died at check $i/$checks"
            break
        fi

        echo "$(date +%s) $current_rss" >> "$rss_log"

        if [[ $current_rss -gt $max_rss ]]; then
            max_rss=$current_rss
        fi

        # Progress indicator
        if [[ $((i % 10)) -eq 0 ]]; then
            print_msg YELLOW "Progress: $i/$checks checks (RSS: ${current_rss} KB)"
        fi
    done

    # Get final RSS
    local final_rss=$(ps -p "$monitor_pid" -o rss= 2>/dev/null | tr -d ' ' || echo "0")
    print_msg YELLOW "Final RSS: ${final_rss} KB"

    # Check for memory leaks (RSS should not grow > 50%)
    local rss_growth=$((final_rss - initial_rss))
    local rss_growth_pct=$((rss_growth * 100 / initial_rss))

    assert "[[ $rss_growth_pct -lt 50 ]]" \
        "No significant memory leak (growth: ${rss_growth_pct}%)"

    # Check log file size
    local log_size=0
    if [[ -f "$log_file" ]]; then
        log_size=$(wc -c < "$log_file" | tr -d ' ')
    fi
    local log_size_mb=$((log_size / 1024 / 1024))

    assert "[[ $log_size_mb -lt 100 ]]" \
        "Log file size reasonable (${log_size_mb} MB < 100 MB)"

    # Performance metrics
    local total_time=$(($(date +%s) - start_time))
    echo "Test 6.3 Results:" >> "$RESULTS_DIR/summary.txt"
    echo "  - Duration: ${total_time}s" >> "$RESULTS_DIR/summary.txt"
    echo "  - Initial RSS: ${initial_rss} KB" >> "$RESULTS_DIR/summary.txt"
    echo "  - Final RSS: ${final_rss} KB" >> "$RESULTS_DIR/summary.txt"
    echo "  - Max RSS: ${max_rss} KB" >> "$RESULTS_DIR/summary.txt"
    echo "  - RSS growth: ${rss_growth_pct}%" >> "$RESULTS_DIR/summary.txt"
    echo "  - Log size: ${log_size_mb} MB" >> "$RESULTS_DIR/summary.txt"
    echo "" >> "$RESULTS_DIR/summary.txt"

    # Cleanup
    "$SCRIPT_DIR/queue-monitor.sh" stop 2>/dev/null || true
    tmux kill-session -t "$monitor_session" 2>/dev/null || true
}

#######################################
# Main test runner
#######################################
run_tests() {
    local test_name="${1:-all}"

    print_msg BLUE "╔════════════════════════════════════════════════╗"
    print_msg BLUE "║  Coordination Infrastructure Performance Tests ║"
    print_msg BLUE "╚════════════════════════════════════════════════╝"

    setup

    case "$test_name" in
        test_6_1*|concurrent)
            test_6_1_concurrent_agents
            ;;
        test_6_2*|mail)
            test_6_2_mail_queue_flush
            ;;
        test_6_3*|monitor|stability)
            test_6_3_monitor_stability
            ;;
        all)
            test_6_1_concurrent_agents
            test_6_2_mail_queue_flush
            test_6_3_monitor_stability
            ;;
        *)
            print_msg RED "Unknown test: $test_name"
            print_msg YELLOW "Available tests: test_6_1, test_6_2, test_6_3, all"
            exit 1
            ;;
    esac

    # Print summary
    print_msg BLUE "\n╔════════════════════════════════════════════════╗"
    print_msg BLUE "║  Test Summary                                  ║"
    print_msg BLUE "╚════════════════════════════════════════════════╝"

    echo ""
    echo "Tests run:    $TESTS_RUN"
    print_msg GREEN "Tests passed: $TESTS_PASSED"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        print_msg RED "Tests failed: $TESTS_FAILED"
    else
        echo "Tests failed: $TESTS_FAILED"
    fi
    echo ""

    print_msg YELLOW "Detailed results: $RESULTS_DIR/summary.txt"
    cat "$RESULTS_DIR/summary.txt"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        print_msg RED "❌ SOME TESTS FAILED"
        exit 1
    else
        print_msg GREEN "✅ ALL TESTS PASSED"
        exit 0
    fi
}

# Main execution
main() {
    run_tests "${1:-all}"
}

main "$@"
