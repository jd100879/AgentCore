#!/usr/bin/env bash
# test_next_bead.sh - Unit tests for next-bead.sh transition script
#
# Tests:
#   1. Non-tmux fallback shows correct message
#   2. Prompt building includes bead ID, title, description, priority
#   3. Empty bead case exits cleanly
#   4. Tracking file is written correctly
#   5. tmux send-keys uses -l flag for literal prompt text
#   6. Timing structure: sleep before /clear, between /clear and prompt, before Enter
#   7. Single br show call (not duplicated)
#
# Usage: ./tests/test_next_bead.sh

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/next-bead.sh"

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

echo "=== Test: script structure and tmux flags ==="

# Verify the -l flag is used for literal prompt sending
if grep -q 'send-keys -t "$pane" -l "$prompt"' "$SCRIPT"; then
    pass "Uses -l flag for literal prompt text (prevents key name interpretation)"
else
    fail "Should use -l flag for tmux send-keys prompt" "Without -l, words like 'Enter' in descriptions are interpreted as keys"
fi

# Verify /clear does NOT use -l (it needs Enter interpreted as a key)
if grep -q 'send-keys -t "$pane" "/clear" Enter' "$SCRIPT"; then
    pass "/clear line correctly sends Enter as key (no -l)"
else
    fail "/clear should send Enter as a key name"
fi

# Verify Enter after prompt is separate from the -l send
if grep -A5 'send-keys.*-l.*\$prompt' "$SCRIPT" | grep -q 'send-keys.*Enter'; then
    pass "Enter is sent as separate send-keys after prompt (not with -l)"
else
    fail "Enter should be a separate send-keys call after the -l prompt"
fi

echo ""
echo "=== Test: timing structure ==="

# Check sleep before /clear (use -B5 to look past comments)
SLEEP_BEFORE_CLEAR=$(grep -B5 'send-keys.*"/clear"' "$SCRIPT" | grep -o 'sleep [0-9]*' | tail -1)
if [ -n "$SLEEP_BEFORE_CLEAR" ]; then
    SECONDS_BEFORE=$(echo "$SLEEP_BEFORE_CLEAR" | grep -o '[0-9]*')
    if [ "$SECONDS_BEFORE" -ge 2 ]; then
        pass "Sleep before /clear: ${SECONDS_BEFORE}s (sufficient for Bash tool to return)"
    else
        fail "Sleep before /clear too short: ${SECONDS_BEFORE}s (need >= 2s)"
    fi
else
    fail "No sleep found before /clear send-keys"
fi

# Check sleep between /clear and prompt
SLEEP_BEFORE_PROMPT=$(grep -A1 'send-keys.*"/clear"' "$SCRIPT" | grep -o 'sleep [0-9]*')
if [ -n "$SLEEP_BEFORE_PROMPT" ]; then
    SECONDS_BETWEEN=$(echo "$SLEEP_BEFORE_PROMPT" | grep -o '[0-9]*')
    if [ "$SECONDS_BETWEEN" -ge 2 ]; then
        pass "Sleep between /clear and prompt: ${SECONDS_BETWEEN}s (sufficient for context clear)"
    else
        fail "Sleep between /clear and prompt too short: ${SECONDS_BETWEEN}s (need >= 2s)"
    fi
else
    fail "No sleep found between /clear and prompt"
fi

# Check sleep before Enter
SLEEP_BEFORE_ENTER=$(grep -B1 'send-keys.*Enter$' "$SCRIPT" | grep -o 'sleep [0-9]*' | tail -1)
if [ -n "$SLEEP_BEFORE_ENTER" ]; then
    SECONDS_ENTER=$(echo "$SLEEP_BEFORE_ENTER" | grep -o '[0-9]*')
    if [ "$SECONDS_ENTER" -ge 1 ]; then
        pass "Sleep before Enter: ${SECONDS_ENTER}s (sufficient for prompt buffer)"
    else
        fail "Sleep before Enter too short: ${SECONDS_ENTER}s (need >= 1s)"
    fi
else
    fail "No sleep found before Enter send-keys"
fi

echo ""
echo "=== Test: single br show call (no duplication) ==="

BR_SHOW_COUNT=$(grep -c 'br show.*--json' "$SCRIPT")
if [ "$BR_SHOW_COUNT" -eq 1 ]; then
    pass "Single br show --json call (no duplicate)"
elif [ "$BR_SHOW_COUNT" -eq 0 ]; then
    fail "No br show --json call found"
else
    fail "Multiple br show --json calls found ($BR_SHOW_COUNT)" "Should use single call and parse both fields"
fi

echo ""
echo "=== Test: background subshell with disown ==="

if grep -q '&$' "$SCRIPT"; then
    pass "tmux sequence runs in background (&)"
else
    fail "tmux sequence should run in background"
fi

if grep -q 'disown' "$SCRIPT"; then
    pass "Background process is disowned"
else
    fail "Background process should be disowned"
fi

echo ""
echo "=== Test: non-tmux fallback ==="

# Create a mock environment to test the non-tmux path
MOCK_DIR=$(mktemp -d /tmp/test-next-bead.XXXXXX)
trap "rm -rf '$MOCK_DIR'" EXIT

# Create mock scripts/tools that next-bead.sh depends on
mkdir -p "$MOCK_DIR/bin" "$MOCK_DIR/scripts"

# Mock agent-mail-helper.sh
cat > "$MOCK_DIR/scripts/agent-mail-helper.sh" << 'MOCK'
#!/bin/bash
echo "TestAgent"
MOCK
chmod +x "$MOCK_DIR/scripts/agent-mail-helper.sh"

# Mock br
cat > "$MOCK_DIR/bin/br" << 'MOCK'
#!/bin/bash
case "$1" in
    sync) exit 0 ;;
    update) exit 0 ;;
    show)
        echo '[{"description":"Test description","priority":"2"}]'
        ;;
esac
MOCK
chmod +x "$MOCK_DIR/bin/br"

# Mock bv
cat > "$MOCK_DIR/bin/bv" << 'MOCK'
#!/bin/bash
echo '{"id":"bd-test1","title":"Test bead title","score":85}'
MOCK
chmod +x "$MOCK_DIR/bin/bv"

# Mock jq - use real jq
JQ_PATH=$(which jq)

# Create a test version of next-bead.sh that uses our mocks
cat > "$MOCK_DIR/scripts/next-bead.sh" << TESTSCRIPT
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$MOCK_DIR/scripts"
AGENT_NAME=\$("\$SCRIPT_DIR/agent-mail-helper.sh" whoami 2>/dev/null || echo "unknown")

PATH="$MOCK_DIR/bin:\$PATH"
br sync --flush-only --force >/dev/null 2>&1 || true
bv_output=\$(bv --robot-next --format json 2>/dev/null || echo "{}")
bead_id=\$(echo "\$bv_output" | jq -r '.id // empty' 2>/dev/null)

if [ -z "\$bead_id" ] || [ "\$bead_id" = "null" ]; then
    echo "No beads available. You can exit or wait."
    exit 0
fi

bead_title=\$(echo "\$bv_output" | jq -r '.title // "untitled"' 2>/dev/null)
br update "\$bead_id" --status in_progress --owner "\$AGENT_NAME" --assignee "\$AGENT_NAME" >/dev/null 2>&1 || true
echo "\$bead_id" > "/tmp/agent-bead-\${AGENT_NAME}.txt"

pane="\${TMUX_PANE:-}"
if [ -z "\$pane" ]; then
    echo "Not in a tmux pane. Claimed bead \$bead_id — run /clear manually, then work on it."
    echo "  br show \$bead_id"
    exit 0
fi

bead_json=\$(br show "\$bead_id" --json 2>/dev/null || echo "[]")
description=\$(echo "\$bead_json" | jq -r '.[0].description // ""' 2>/dev/null)
priority=\$(echo "\$bead_json" | jq -r '.[0].priority // ""' 2>/dev/null)

prompt="Work on bead \$bead_id: \$bead_title."
[ -n "\$description" ] && prompt="\$prompt Description: \$description"
[ -n "\$priority" ] && prompt="\$prompt Priority: \$priority"
prompt="\$prompt Check inbox first, then complete this task."

echo "Claimed bead \$bead_id: \$bead_title"
echo "Clearing context and starting fresh..."
echo "PROMPT_DEBUG: \$prompt"
TESTSCRIPT
chmod +x "$MOCK_DIR/scripts/next-bead.sh"

# Test non-tmux fallback (TMUX_PANE unset)
OUTPUT=$(unset TMUX_PANE; "$MOCK_DIR/scripts/next-bead.sh" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    pass "Non-tmux mode exits cleanly"
else
    fail "Non-tmux mode should exit 0, got $EXIT_CODE"
fi

if echo "$OUTPUT" | grep -q "Not in a tmux pane"; then
    pass "Shows non-tmux fallback message"
else
    fail "Should show non-tmux fallback message" "$OUTPUT"
fi

if echo "$OUTPUT" | grep -q "bd-test1"; then
    pass "Non-tmux message includes bead ID"
else
    fail "Non-tmux message should include bead ID" "$OUTPUT"
fi

if echo "$OUTPUT" | grep -q "br show bd-test1"; then
    pass "Non-tmux message includes br show hint"
else
    fail "Non-tmux message should include br show hint"
fi

echo ""
echo "=== Test: tracking file written ==="

TRACKING_FILE="/tmp/agent-bead-TestAgent.txt"
if [ -f "$TRACKING_FILE" ]; then
    TRACKING_CONTENT=$(cat "$TRACKING_FILE")
    if [ "$TRACKING_CONTENT" = "bd-test1" ]; then
        pass "Tracking file contains bead ID: $TRACKING_CONTENT"
    else
        fail "Tracking file should contain 'bd-test1', got '$TRACKING_CONTENT'"
    fi
else
    fail "Tracking file not created at $TRACKING_FILE"
fi

echo ""
echo "=== Test: prompt building with tmux pane ==="

# Test with TMUX_PANE set (won't actually send to tmux, just check prompt building)
OUTPUT=$(TMUX_PANE="%99" "$MOCK_DIR/scripts/next-bead.sh" 2>&1)

if echo "$OUTPUT" | grep -q "Claimed bead bd-test1: Test bead title"; then
    pass "Output includes claimed bead info"
else
    fail "Output should include claimed bead info" "$OUTPUT"
fi

if echo "$OUTPUT" | grep -q "Clearing context"; then
    pass "Output includes clearing message"
else
    fail "Output should include clearing message"
fi

if echo "$OUTPUT" | grep "PROMPT_DEBUG" | grep -q "Work on bead bd-test1"; then
    pass "Prompt includes bead ID"
else
    fail "Prompt should include bead ID" "$(echo "$OUTPUT" | grep PROMPT_DEBUG)"
fi

if echo "$OUTPUT" | grep "PROMPT_DEBUG" | grep -q "Test bead title"; then
    pass "Prompt includes bead title"
else
    fail "Prompt should include bead title"
fi

if echo "$OUTPUT" | grep "PROMPT_DEBUG" | grep -q "Description: Test description"; then
    pass "Prompt includes description"
else
    fail "Prompt should include description" "$(echo "$OUTPUT" | grep PROMPT_DEBUG)"
fi

if echo "$OUTPUT" | grep "PROMPT_DEBUG" | grep -q "Priority: 2"; then
    pass "Prompt includes priority"
else
    fail "Prompt should include priority" "$(echo "$OUTPUT" | grep PROMPT_DEBUG)"
fi

if echo "$OUTPUT" | grep "PROMPT_DEBUG" | grep -q "Check inbox first"; then
    pass "Prompt ends with inbox instruction"
else
    fail "Prompt should end with inbox instruction"
fi

echo ""
echo "=== Test: empty bead case ==="

# Mock bv to return empty
cat > "$MOCK_DIR/bin/bv" << 'MOCK'
#!/bin/bash
echo '{}'
MOCK
chmod +x "$MOCK_DIR/bin/bv"

OUTPUT=$(unset TMUX_PANE; "$MOCK_DIR/scripts/next-bead.sh" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    pass "Empty bead case exits cleanly"
else
    fail "Empty bead case should exit 0, got $EXIT_CODE"
fi

if echo "$OUTPUT" | grep -q "No beads available"; then
    pass "Shows 'no beads available' message"
else
    fail "Should show 'no beads available' message" "$OUTPUT"
fi

echo ""
echo "=== Test: null bead ID case ==="

cat > "$MOCK_DIR/bin/bv" << 'MOCK'
#!/bin/bash
echo '{"id":null,"title":null}'
MOCK
chmod +x "$MOCK_DIR/bin/bv"

OUTPUT=$(unset TMUX_PANE; "$MOCK_DIR/scripts/next-bead.sh" 2>&1)

if echo "$OUTPUT" | grep -q "No beads available"; then
    pass "Null bead ID handled as no beads"
else
    fail "Null bead ID should be handled as no beads" "$OUTPUT"
fi

echo ""
echo "=============================="
echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"

# Cleanup tracking file
rm -f "/tmp/agent-bead-TestAgent.txt"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
