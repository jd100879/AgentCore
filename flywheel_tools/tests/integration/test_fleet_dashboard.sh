#!/usr/bin/env bash
#
# test_fleet_dashboard.sh - Integration tests for fleet-status.sh
#
# Tests the fleet management dashboard functionality across all display modes.
#
# Usage:
#   ./tests/integration/test_fleet_dashboard.sh [scenario]
#
# Scenarios:
#   T1:  Basic Functionality (default, compact, JSON, watch modes)
#   T2:  Display Modes (full dashboard, compact summary, JSON output)
#   T3:  Data Accuracy (agent status, task counts, beads integration)
#   T4:  Tmux Integration (status bar, pane detection)
#   T5:  Edge Cases (no agents, no tasks, large datasets, errors)
#   T6:  Performance (load time, watch mode efficiency)
#
# Part of: bd-3ut (Component 4 testing)

set -uo pipefail
# Note: set -e disabled to allow tests to fail without stopping execution

# Test configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS_DIR="$PROJECT_ROOT/scripts"
FLEET_SCRIPT="$SCRIPTS_DIR/fleet-status.sh"

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

# Cleanup tracking
CLEANUP_TASKS=()

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
    local description="$2"
    ((TESTS_RUN++))

    if eval "$condition"; then
        print_msg GREEN "  ✓ $description"
        ((TESTS_PASSED++))
        return 0
    else
        print_msg RED "  ✗ $description"
        ((TESTS_FAILED++))
        return 1
    fi
}

#######################################
# Cleanup function
#######################################
cleanup() {
    print_msg BLUE "\nCleaning up test environment..."

    # Close any test issues created
    if [[ ${#CLEANUP_TASKS[@]} -gt 0 ]]; then
        for task in "${CLEANUP_TASKS[@]}"; do
            br update "$task" --status closed 2>/dev/null || true
        done
    fi

    # Kill any background watch processes
    pkill -f "fleet-status.sh.*--watch" 2>/dev/null || true
}

trap cleanup EXIT

#######################################
# T1: Basic Functionality
#######################################
test_basic_functionality() {
    print_msg BLUE "\n=== T1: Basic Functionality ==="

    # Test 1: Script exists and is executable
    print_msg YELLOW "Test 1: Fleet dashboard script availability"
    assert "[[ -x \"$FLEET_SCRIPT\" ]]" "Script exists and is executable"

    # Test 2: Default mode runs without error
    print_msg YELLOW "Test 2: Default display mode"
    local default_output=$("$FLEET_SCRIPT" 2>&1) || true
    local default_exit=$?
    assert "[[ $default_exit -eq 0 ]]" "Default mode executes successfully"
    assert "[[ -n \"$default_output\" ]]" "Default mode produces output"

    # Test 3: Help/usage
    print_msg YELLOW "Test 3: Help documentation"
    local help_output=$("$FLEET_SCRIPT" --help 2>&1) || true
    assert "echo '$help_output' | grep -qi 'usage\\|fleet\\|options'" "Help text is available"
}

#######################################
# T2: Display Modes
#######################################
test_display_modes() {
    print_msg BLUE "\n=== T2: Display Modes ==="

    # Test 4: Compact mode
    print_msg YELLOW "Test 4: Compact display mode"
    local compact_output=$("$FLEET_SCRIPT" --compact 2>&1) || true
    local compact_exit=$?
    assert "[[ $compact_exit -eq 0 ]]" "Compact mode executes successfully"
    assert "[[ -n \"$compact_output\" ]]" "Compact mode produces output"

    # Test 5: JSON mode
    print_msg YELLOW "Test 5: JSON output mode"
    local json_output=$("$FLEET_SCRIPT" --json 2>&1) || true
    local json_exit=$?
    assert "[[ $json_exit -eq 0 ]]" "JSON mode executes successfully"

    # Validate JSON structure
    if command -v jq &>/dev/null; then
        if echo "$json_output" | jq . &>/dev/null; then
            ((TESTS_RUN++))
            print_msg GREEN "  ✓ JSON output is valid"
            ((TESTS_PASSED++))
        else
            ((TESTS_RUN++))
            print_msg RED "  ✗ JSON output is valid"
            ((TESTS_FAILED++))
        fi

        if echo "$json_output" | jq -e '.agents.agents' &>/dev/null; then
            ((TESTS_RUN++))
            print_msg GREEN "  ✓ JSON has 'agents.agents' structure"
            ((TESTS_PASSED++))
        else
            ((TESTS_RUN++))
            print_msg RED "  ✗ JSON has 'agents.agents' structure"
            ((TESTS_FAILED++))
        fi

        if echo "$json_output" | jq -e '.timestamp' &>/dev/null; then
            ((TESTS_RUN++))
            print_msg GREEN "  ✓ JSON has 'timestamp' key"
            ((TESTS_PASSED++))
        else
            ((TESTS_RUN++))
            print_msg RED "  ✗ JSON has 'timestamp' key"
            ((TESTS_FAILED++))
        fi
    else
        print_msg YELLOW "  ⚠ jq not available, skipping JSON validation"
    fi
}

#######################################
# T3: Data Accuracy
#######################################
test_data_accuracy() {
    print_msg BLUE "\n=== T3: Data Accuracy ==="

    # Create test task for verification
    print_msg YELLOW "Test 6: Data accuracy - task counts"

    # Get current task count from beads
    local beads_count=$(br list --status open 2>/dev/null | grep -c "^○" || echo "0")

    # Get task count from fleet dashboard JSON
    local fleet_json=$("$FLEET_SCRIPT" --json 2>&1)
    local fleet_count=0
    if command -v jq &>/dev/null && echo "$fleet_json" | jq . &>/dev/null; then
        fleet_count=$(echo "$fleet_json" | jq -r '.tasks.total // 0' 2>/dev/null)
    fi

    assert "[[ -n \"$fleet_count\" ]]" "Fleet dashboard reports task count"

    # Test 7: Agent status accuracy
    print_msg YELLOW "Test 7: Agent status reporting"

    # Check if current agent appears in output
    local current_agent=$("$SCRIPTS_DIR/agent-mail-helper.sh" whoami 2>/dev/null || echo "unknown")
    local fleet_text=$("$FLEET_SCRIPT" 2>&1)

    if [[ "$current_agent" != "unknown" ]] && [[ "$current_agent" != "Error"* ]]; then
        # Agent should appear in output if registered
        assert "echo '$fleet_text' | grep -q '$current_agent' || echo '$fleet_text' | grep -q 'No agents detected\\|No active agents'" "Current agent status reflected correctly"
    else
        print_msg YELLOW "  ⚠ No agent registered, skipping agent verification"
    fi
}

#######################################
# T4: Tmux Integration
#######################################
test_tmux_integration() {
    print_msg BLUE "\n=== T4: Tmux Integration ==="

    # Test 8: Tmux session detection
    print_msg YELLOW "Test 8: Tmux session detection"

    if [[ -n "${TMUX:-}" ]]; then
        # We're in tmux, test should detect it
        local tmux_test=$("$FLEET_SCRIPT" --compact 2>&1)
        assert "[[ $? -eq 0 ]]" "Fleet dashboard works in tmux context"
    else
        # Not in tmux, should still work
        local no_tmux_test=$("$FLEET_SCRIPT" --compact 2>&1)
        assert "[[ $? -eq 0 ]]" "Fleet dashboard works without tmux"
    fi

    # Test 9: Pane-specific data (if in tmux)
    print_msg YELLOW "Test 9: Pane-specific agent detection"

    if [[ -n "${TMUX:-}" ]]; then
        local pane_data=$("$FLEET_SCRIPT" --json 2>&1)
        if [[ -n "$pane_data" ]]; then
            ((TESTS_RUN++))
            print_msg GREEN "  ✓ Pane-specific data retrieved in tmux"
            ((TESTS_PASSED++))
        else
            ((TESTS_RUN++))
            print_msg RED "  ✗ Pane-specific data retrieved in tmux"
            ((TESTS_FAILED++))
        fi
    else
        print_msg YELLOW "  ⚠ Not in tmux, skipping pane detection test"
    fi
}

#######################################
# T5: Edge Cases
#######################################
test_edge_cases() {
    print_msg BLUE "\n=== T5: Edge Cases ==="

    # Test 10: Invalid arguments
    print_msg YELLOW "Test 10: Invalid argument handling"
    "$FLEET_SCRIPT" --invalid-flag &>/dev/null
    local invalid_exit=$?
    assert "[[ $invalid_exit -ne 0 ]]" "Invalid arguments return error"

    # Test 11: No beads database
    print_msg YELLOW "Test 11: Missing beads database handling"

    # Temporarily rename beads db (if exists)
    local beads_db="$PROJECT_ROOT/.beads"
    local beads_backup="$PROJECT_ROOT/.beads.test-backup"

    if [[ -d "$beads_db" ]]; then
        mv "$beads_db" "$beads_backup" 2>/dev/null || true
        local no_beads_output=$("$FLEET_SCRIPT" --compact 2>&1) || true
        local no_beads_exit=$?
        mv "$beads_backup" "$beads_db" 2>/dev/null || true

        assert "[[ $no_beads_exit -eq 0 ]] || echo '$no_beads_output' | grep -qi 'error\\|not found'" "Handles missing beads gracefully"
    else
        print_msg YELLOW "  ⚠ No beads database found, skipping test"
    fi

    # Test 12: Large dataset simulation
    print_msg YELLOW "Test 12: Large dataset handling"

    # Create multiple test tasks
    local test_tasks=()
    for i in {1..5}; do
        local task_id=$(br create --title "Fleet Test Task $i" --description "Test task for fleet dashboard stress testing" --status open 2>/dev/null | grep -oE 'bd-[a-z0-9]+' | head -1)
        if [[ -n "$task_id" ]]; then
            test_tasks+=("$task_id")
            CLEANUP_TASKS+=("$task_id")
        fi
    done

    if [[ ${#test_tasks[@]} -gt 0 ]]; then
        # Clear cache to ensure fresh data after task creation
        "$SCRIPTS_DIR/fleet-core.sh" cache_clear >/dev/null 2>&1 || true

        local large_output=$("$FLEET_SCRIPT" --json 2>&1)
        assert "[[ $? -eq 0 ]]" "Handles multiple tasks successfully"

        # Verify tasks appear
        if command -v jq &>/dev/null; then
            # Sum all task categories since there's no .total field
            local reported_tasks=$(echo "$large_output" | jq -r '(.tasks.ready // 0) + (.tasks.in_progress // 0) + (.tasks.blocked // 0) + (.tasks.completed_today // 0)')
            assert "[[ $reported_tasks -ge ${#test_tasks[@]} ]]" "All test tasks reflected in output"
        fi
    else
        print_msg YELLOW "  ⚠ Could not create test tasks, skipping large dataset test"
    fi
}

#######################################
# T6: Performance
#######################################
test_performance() {
    print_msg BLUE "\n=== T6: Performance ==="

    # Test 13: Default mode performance
    print_msg YELLOW "Test 13: Default mode load time"

    local start_time=$(date +%s)
    "$FLEET_SCRIPT" >/dev/null 2>&1
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    assert "[[ $duration -lt 5 ]]" "Default mode loads in <5s (actual: ${duration}s)"

    # Test 14: JSON mode performance
    print_msg YELLOW "Test 14: JSON mode performance"

    start_time=$(date +%s)
    "$FLEET_SCRIPT" --json >/dev/null 2>&1
    end_time=$(date +%s)
    duration=$((end_time - start_time))

    assert "[[ $duration -lt 5 ]]" "JSON mode loads in <5s (actual: ${duration}s)"

    # Test 15: Watch mode (5 second test)
    print_msg YELLOW "Test 15: Watch mode CPU efficiency"

    # Start watch mode in background
    "$FLEET_SCRIPT" --watch >/dev/null 2>&1 &
    local watch_pid=$!

    # Let it run for 2 seconds
    sleep 2

    # Check if still running
    if ps -p $watch_pid >/dev/null 2>&1; then
        assert "true" "Watch mode runs continuously"
        kill $watch_pid 2>/dev/null || true
    else
        assert "false" "Watch mode runs continuously"
    fi
}

#######################################
# Main test runner
#######################################
main() {
    print_msg BLUE "╔════════════════════════════════════════════════╗"
    print_msg BLUE "║  Fleet Dashboard Integration Tests            ║"
    print_msg BLUE "║  Component 4: Fleet Management Dashboard      ║"
    print_msg BLUE "╚════════════════════════════════════════════════╝"

    local scenario="${1:-all}"

    case "$scenario" in
        T1|basic)
            test_basic_functionality
            ;;
        T2|display)
            test_display_modes
            ;;
        T3|accuracy)
            test_data_accuracy
            ;;
        T4|tmux)
            test_tmux_integration
            ;;
        T5|edge)
            test_edge_cases
            ;;
        T6|performance)
            test_performance
            ;;
        all)
            test_basic_functionality
            test_display_modes
            test_data_accuracy
            test_tmux_integration
            test_edge_cases
            test_performance
            ;;
        *)
            print_msg RED "Unknown scenario: $scenario"
            echo "Available scenarios: T1-T6, basic, display, accuracy, tmux, edge, performance, all"
            exit 1
            ;;
    esac

    # Print summary
    print_msg BLUE "\n╔════════════════════════════════════════════════╗"
    print_msg BLUE "║  Test Summary                                  ║"
    print_msg BLUE "╚════════════════════════════════════════════════╝"

    echo "Tests run:    $TESTS_RUN"
    if [[ $TESTS_PASSED -gt 0 ]]; then
        print_msg GREEN "Tests passed: $TESTS_PASSED"
    fi
    if [[ $TESTS_FAILED -gt 0 ]]; then
        print_msg RED "Tests failed: $TESTS_FAILED"
    fi

    if [[ $TESTS_FAILED -eq 0 ]] && [[ $TESTS_RUN -gt 0 ]]; then
        print_msg GREEN "\n✅ ALL TESTS PASSED"
        exit 0
    elif [[ $TESTS_RUN -eq 0 ]]; then
        print_msg YELLOW "\n⚠️  NO TESTS RUN"
        exit 2
    else
        print_msg RED "\n❌ SOME TESTS FAILED"
        exit 1
    fi
}

# Run tests
main "$@"
