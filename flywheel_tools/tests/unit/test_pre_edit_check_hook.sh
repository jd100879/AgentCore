#!/usr/bin/env bash
# test_pre_edit_check_hook.sh - Unit tests for pre-edit-check-hook.sh
#
# Tests the Claude Code pre-edit hook that enforces bead workflow:
#   1. Blocks edits when no active bead (blocking mode)
#   2. Allows edits when AGENT_RUNNER_BEAD env var is set
#   3. Allows edits when tracking file exists
#   4. Handles missing file_path gracefully
#   5. Logs edit_blocked/edit_allowed events
#
# Usage: ./tests/test_pre_edit_check_hook.sh

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

# Create isolated test environment
TMPDIR=$(mktemp -d /tmp/test-pre-edit-hook.XXXXXX)
trap "rm -rf '$TMPDIR'" EXIT

mkdir -p "$TMPDIR/scripts" "$TMPDIR/.beads"

# Create mock agent-mail-helper.sh
cat > "$TMPDIR/scripts/agent-mail-helper.sh" << 'MOCK'
#!/bin/bash
echo "TestAgent"
MOCK
chmod +x "$TMPDIR/scripts/agent-mail-helper.sh"

# Create mock log-bead-activity.sh (records calls to a log file)
cat > "$TMPDIR/scripts/log-bead-activity.sh" << MOCK
#!/bin/bash
echo "\$@" >> "$TMPDIR/activity-log.txt"
MOCK
chmod +x "$TMPDIR/scripts/log-bead-activity.sh"

# Create mock pre-edit-check.sh (always passes)
cat > "$TMPDIR/scripts/pre-edit-check.sh" << 'MOCK'
#!/bin/bash
# Always report files available
echo "✓ Pre-edit check passed - files are available"
exit 0
MOCK
chmod +x "$TMPDIR/scripts/pre-edit-check.sh"

# Create test hook script pointing to our mocks
TEST_HOOK="$TMPDIR/scripts/pre-edit-check-hook.sh"
cat > "$TEST_HOOK" << HOOK
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$TMPDIR/scripts"
PRE_EDIT_CHECK="\$SCRIPT_DIR/pre-edit-check.sh"
LOG_SCRIPT="\$SCRIPT_DIR/log-bead-activity.sh"

INPUT=\$(cat)
FILE_PATH=\$(echo "\$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "\$FILE_PATH" ]; then
    exit 0
fi

AGENT_NAME=\$("\$SCRIPT_DIR/agent-mail-helper.sh" whoami 2>/dev/null || echo "unknown")
ENFORCEMENT_MODE="blocking"

BEAD_ID="\${AGENT_RUNNER_BEAD:-}"

if [ -z "\$BEAD_ID" ]; then
    BEAD_TRACKING_FILE="/tmp/agent-bead-\${AGENT_NAME}.txt"
    if [ -f "\$BEAD_TRACKING_FILE" ]; then
        BEAD_ID=\$(cat "\$BEAD_TRACKING_FILE")
    fi
fi

if [ -z "\$BEAD_ID" ]; then
    echo "⚠️  No active bead claimed!" >&2
    if [ "\$ENFORCEMENT_MODE" = "blocking" ]; then
        echo "❌ Edit blocked: Claim a bead first" >&2
        if [ -f "\$LOG_SCRIPT" ]; then
            "\$LOG_SCRIPT" "none" "edit_blocked" "\$AGENT_NAME"
        fi
        exit 2
    else
        echo "ℹ️  Proceeding anyway (advisory mode)" >&2
        if [ -f "\$LOG_SCRIPT" ]; then
            "\$LOG_SCRIPT" "none" "edit_allowed_without_bead" "\$AGENT_NAME"
        fi
    fi
else
    echo "✓ Active bead: \$BEAD_ID" >&2
    if [ -f "\$LOG_SCRIPT" ]; then
        "\$LOG_SCRIPT" "\$BEAD_ID" "edit_allowed" "\$AGENT_NAME"
    fi
fi

if "\$PRE_EDIT_CHECK" "\$FILE_PATH" >&2; then
    exit 0
else
    exit 2
fi
HOOK
chmod +x "$TEST_HOOK"

# Helper to send hook input
run_hook() {
    local file_path="${1:-}"
    local env_bead="${2:-}"
    local json='{"tool_input":{"file_path":"'"$file_path"'"}}'

    if [ -n "$env_bead" ]; then
        echo "$json" | AGENT_RUNNER_BEAD="$env_bead" "$TEST_HOOK" 2>&1
    else
        echo "$json" | unset AGENT_RUNNER_BEAD; echo "$json" | "$TEST_HOOK" 2>&1
    fi
}

run_hook_exit() {
    local file_path="${1:-}"
    local env_bead="${2:-}"
    local json='{"tool_input":{"file_path":"'"$file_path"'"}}'
    local exit_code=0

    if [ -n "$env_bead" ]; then
        echo "$json" | AGENT_RUNNER_BEAD="$env_bead" "$TEST_HOOK" >/dev/null 2>&1 || exit_code=$?
    else
        echo "$json" | "$TEST_HOOK" >/dev/null 2>&1 || exit_code=$?
    fi
    echo "$exit_code"
}

echo "=== Test: empty file_path allows edit ==="

EXIT_CODE=0
echo '{"tool_input":{}}' | "$TEST_HOOK" >/dev/null 2>&1 || EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    pass "Empty file_path exits 0 (allow)"
else
    fail "Empty file_path should exit 0, got $EXIT_CODE"
fi

echo ""
echo "=== Test: blocks edit when no active bead ==="

# Ensure no tracking file and no env var
rm -f "/tmp/agent-bead-TestAgent.txt"

EXIT_CODE=0
echo '{"tool_input":{"file_path":"src/app.py"}}' | env -u AGENT_RUNNER_BEAD "$TEST_HOOK" >/dev/null 2>&1 || EXIT_CODE=$?

if [ $EXIT_CODE -eq 2 ]; then
    pass "Blocks edit (exit 2) when no bead"
else
    fail "Should block edit with exit 2, got $EXIT_CODE"
fi

# Check that edit_blocked was logged
> "$TMPDIR/activity-log.txt"  # clear
echo '{"tool_input":{"file_path":"src/app.py"}}' | env -u AGENT_RUNNER_BEAD "$TEST_HOOK" >/dev/null 2>&1 || true

if grep -q "edit_blocked" "$TMPDIR/activity-log.txt"; then
    pass "Logs edit_blocked event"
else
    fail "Should log edit_blocked event" "$(cat "$TMPDIR/activity-log.txt")"
fi

echo ""
echo "=== Test: allows edit when AGENT_RUNNER_BEAD is set ==="

> "$TMPDIR/activity-log.txt"
EXIT_CODE=0
echo '{"tool_input":{"file_path":"src/app.py"}}' | AGENT_RUNNER_BEAD="bd-env1" "$TEST_HOOK" >/dev/null 2>&1 || EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    pass "Allows edit when AGENT_RUNNER_BEAD set"
else
    fail "Should allow edit with env var, got $EXIT_CODE"
fi

if grep -q "edit_allowed" "$TMPDIR/activity-log.txt"; then
    pass "Logs edit_allowed event"
else
    fail "Should log edit_allowed event"
fi

if grep -q "bd-env1" "$TMPDIR/activity-log.txt"; then
    pass "Log includes bead ID from env var"
else
    fail "Log should include bead ID bd-env1" "$(cat "$TMPDIR/activity-log.txt")"
fi

echo ""
echo "=== Test: allows edit when tracking file exists ==="

# Create tracking file
echo "bd-track1" > "/tmp/agent-bead-TestAgent.txt"

> "$TMPDIR/activity-log.txt"
EXIT_CODE=0
echo '{"tool_input":{"file_path":"src/app.py"}}' | env -u AGENT_RUNNER_BEAD "$TEST_HOOK" >/dev/null 2>&1 || EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    pass "Allows edit when tracking file exists"
else
    fail "Should allow edit with tracking file, got $EXIT_CODE"
fi

if grep -q "bd-track1" "$TMPDIR/activity-log.txt"; then
    pass "Uses bead ID from tracking file"
else
    fail "Should use bead ID from tracking file" "$(cat "$TMPDIR/activity-log.txt")"
fi

# Cleanup tracking file
rm -f "/tmp/agent-bead-TestAgent.txt"

echo ""
echo "=== Test: AGENT_RUNNER_BEAD takes priority over tracking file ==="

echo "bd-file1" > "/tmp/agent-bead-TestAgent.txt"

> "$TMPDIR/activity-log.txt"
echo '{"tool_input":{"file_path":"src/app.py"}}' | AGENT_RUNNER_BEAD="bd-env2" "$TEST_HOOK" >/dev/null 2>&1 || true

if grep -q "bd-env2" "$TMPDIR/activity-log.txt"; then
    pass "Env var takes priority over tracking file"
else
    fail "Env var should take priority" "$(cat "$TMPDIR/activity-log.txt")"
fi

# Cleanup
rm -f "/tmp/agent-bead-TestAgent.txt"

echo ""
echo "=== Test: stderr output includes bead status ==="

echo "bd-xyz" > "/tmp/agent-bead-TestAgent.txt"
OUTPUT=$(echo '{"tool_input":{"file_path":"test.py"}}' | env -u AGENT_RUNNER_BEAD "$TEST_HOOK" 2>&1)

if echo "$OUTPUT" | grep -q "Active bead: bd-xyz"; then
    pass "Stderr shows active bead ID"
else
    fail "Should show active bead in stderr" "$OUTPUT"
fi

rm -f "/tmp/agent-bead-TestAgent.txt"

echo ""
echo "=============================="
echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
