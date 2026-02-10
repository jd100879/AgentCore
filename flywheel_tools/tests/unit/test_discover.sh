#!/usr/bin/env bash
# test_discover.sh - Unit tests for panes/discover.sh
#
# Tests:
#   1. sed pattern: safe-pane-name → tmux pane ID conversion
#   2. --all mode: preserves identity files for active panes
#   3. --all mode: archives identity files for stale panes
#   4. --all mode: archives stale agent-name files
#   5. --all mode: cleans up stale lock files
#   6. Edge cases: multi-hyphen session names, single-segment names
#
# Usage: ./tests/test_discover.sh

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
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

# ============================================================
# Section 1: sed pattern tests (isolated, no tmux required)
# ============================================================
# The sed pattern in discover.sh line ~109 converts safe-pane names
# (hyphens only) back to tmux pane IDs (session:window.pane).
# Pattern: sed 's/\(.*\)-/\1./; s/\(.*\)-/\1:/'
# This replaces the LAST hyphen with '.', then the new LAST hyphen with ':'

echo "=== Test: sed pattern - simple session name ==="

# e.g. flywheel-1-6 → flywheel:1.6
RESULT=$(echo "flywheel-1-6" | sed 's/\(.*\)-/\1./; s/\(.*\)-/\1:/')
if [ "$RESULT" = "flywheel:1.6" ]; then
    pass "flywheel-1-6 → flywheel:1.6"
else
    fail "flywheel-1-6 should become flywheel:1.6" "got: $RESULT"
fi

echo ""
echo "=== Test: sed pattern - multi-hyphen session name ==="

# e.g. agent-flywheel-integration-1-1 → agent-flywheel-integration:1.1
RESULT=$(echo "agent-flywheel-integration-1-1" | sed 's/\(.*\)-/\1./; s/\(.*\)-/\1:/')
if [ "$RESULT" = "agent-flywheel-integration:1.1" ]; then
    pass "agent-flywheel-integration-1-1 → agent-flywheel-integration:1.1"
else
    fail "agent-flywheel-integration-1-1 should become agent-flywheel-integration:1.1" "got: $RESULT"
fi

echo ""
echo "=== Test: sed pattern - another multi-hyphen name ==="

# e.g. besteman-land-cattle-1-4 → besteman-land-cattle:1.4
RESULT=$(echo "besteman-land-cattle-1-4" | sed 's/\(.*\)-/\1./; s/\(.*\)-/\1:/')
if [ "$RESULT" = "besteman-land-cattle:1.4" ]; then
    pass "besteman-land-cattle-1-4 → besteman-land-cattle:1.4"
else
    fail "besteman-land-cattle-1-4 should become besteman-land-cattle:1.4" "got: $RESULT"
fi

echo ""
echo "=== Test: sed pattern - single char session ==="

# e.g. a-1-2 → a:1.2
RESULT=$(echo "a-1-2" | sed 's/\(.*\)-/\1./; s/\(.*\)-/\1:/')
if [ "$RESULT" = "a:1.2" ]; then
    pass "a-1-2 → a:1.2"
else
    fail "a-1-2 should become a:1.2" "got: $RESULT"
fi

echo ""
echo "=== Test: sed pattern - double-digit window/pane ==="

# e.g. my-session-12-3 → my-session:12.3
RESULT=$(echo "my-session-12-3" | sed 's/\(.*\)-/\1./; s/\(.*\)-/\1:/')
if [ "$RESULT" = "my-session:12.3" ]; then
    pass "my-session-12-3 → my-session:12.3"
else
    fail "my-session-12-3 should become my-session:12.3" "got: $RESULT"
fi

echo ""
echo "=== Test: sed pattern - deeply hyphenated session name ==="

# e.g. my-super-long-name-here-2-7 → my-super-long-name-here:2.7
RESULT=$(echo "my-super-long-name-here-2-7" | sed 's/\(.*\)-/\1./; s/\(.*\)-/\1:/')
if [ "$RESULT" = "my-super-long-name-here:2.7" ]; then
    pass "my-super-long-name-here-2-7 → my-super-long-name-here:2.7"
else
    fail "my-super-long-name-here-2-7 should become my-super-long-name-here:2.7" "got: $RESULT"
fi


# ============================================================
# Section 2: --all mode preserve/archive tests (mocked tmux)
# ============================================================
# These tests create a fake project directory with identity and
# agent-name files, mock tmux to report only specific panes as
# live, then run the --all cleanup logic and verify results.

echo ""
echo "=== Test: --all mode setup ==="

# Create isolated test environment
TMPDIR=$(mktemp -d /tmp/test-discover.XXXXXX)
trap "rm -rf '$TMPDIR'" EXIT

# Set up project directory structure
TEST_PROJECT="$TMPDIR/project"
mkdir -p "$TEST_PROJECT"/{panes,pids,archive/panes,scripts/lib,state/{snapshots,logs},.ntm/logs,.agent-workflows,.active-agents,.agent-coordination/status,workflows}

# Create a minimal project-config.sh for the test
cat > "$TEST_PROJECT/scripts/lib/project-config.sh" << 'EOF'
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
PIDS_DIR="$PROJECT_ROOT/pids"
PANES_DIR="$PROJECT_ROOT/panes"
SCRIPTS_DIR="$PROJECT_ROOT/scripts"
LOGS_DIR="$PROJECT_ROOT/.ntm/logs"
export PROJECT_ROOT PIDS_DIR PANES_DIR SCRIPTS_DIR LOGS_DIR
init_project_directories() { true; }
EOF

# Create a mock auto-register-agent.sh (should never be called in --all mode)
cat > "$TEST_PROJECT/scripts/auto-register-agent.sh" << 'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$TEST_PROJECT/scripts/auto-register-agent.sh"

# Create identity files:
# - Active pane: agent-flywheel-integration-1-1 (will be listed by mock tmux)
# - Active pane: besteman-land-cattle-1-2 (will be listed by mock tmux)
# - Stale pane: besteman-land-cattle-1-3 (NOT in mock tmux)
# - Stale pane: old-session-1-4 (NOT in mock tmux)

echo '{"pane":"agent-flywheel-integration:1.1","name":"Claude 1","type":"claude-code","agent_mail_name":"SilentRobin"}' \
    > "$TEST_PROJECT/panes/agent-flywheel-integration-1-1.identity"

echo '{"pane":"besteman-land-cattle:1.2","name":"Claude 2","type":"claude-code","agent_mail_name":"BlackSparrow"}' \
    > "$TEST_PROJECT/panes/besteman-land-cattle-1-2.identity"

echo '{"pane":"besteman-land-cattle:1.3","name":"Claude 3","type":"claude-code","agent_mail_name":"IvoryMarsh"}' \
    > "$TEST_PROJECT/panes/besteman-land-cattle-1-3.identity"

echo '{"pane":"old-session:1.4","name":"Claude 4","type":"claude-code","agent_mail_name":"GoldenHawk"}' \
    > "$TEST_PROJECT/panes/old-session-1-4.identity"

# Create agent-name files (matching the above panes)
echo "SilentRobin" > "$TEST_PROJECT/pids/agent-flywheel-integration-1-1.agent-name"
echo "BlackSparrow" > "$TEST_PROJECT/pids/besteman-land-cattle-1-2.agent-name"
echo "IvoryMarsh" > "$TEST_PROJECT/pids/besteman-land-cattle-1-3.agent-name"
echo "GoldenHawk" > "$TEST_PROJECT/pids/old-session-1-4.agent-name"

# Create a lock file (should always get archived)
touch "$TEST_PROJECT/panes/some-stale.lock"

# Create mock tmux that reports only 2 live panes
MOCK_TMUX="$TMPDIR/tmux"
cat > "$MOCK_TMUX" << 'MOCK_EOF'
#!/bin/bash
# Mock tmux - only responds to list-panes -a
if [ "$1" = "list-panes" ] && [ "$2" = "-a" ]; then
    echo "agent-flywheel-integration:1.1"
    echo "besteman-land-cattle:1.2"
fi
# All other commands (display-message, set-option) silently succeed
exit 0
MOCK_EOF
chmod +x "$MOCK_TMUX"

# Create a trimmed version of discover.sh --all logic for testing
# (We extract just the cleanup portion, bypassing the per-pane discovery loop)
cat > "$TMPDIR/test-discover-all.sh" << 'SCRIPT_EOF'
#!/bin/bash
set -uo pipefail

# Override tmux to use our mock
export PATH="MOCK_DIR:$PATH"

export PROJECT_ROOT="TEST_PROJECT_DIR"
source "$PROJECT_ROOT/scripts/lib/project-config.sh"

# --- BEGIN: extracted from discover.sh --all mode (lines 82-120) ---

# Cleanup stale identity files
ARCHIVE_DIR="$PROJECT_ROOT/archive/panes"
mkdir -p "$ARCHIVE_DIR"

for identity_file in "$PANES_DIR/"*.identity; do
    [ -f "$identity_file" ] || continue

    pane_id=$(jq -r '.pane // empty' "$identity_file" 2>/dev/null)
    if [ -n "$pane_id" ]; then
        if ! tmux list-panes -a -F "#{session_name}:#{window_index}.#{pane_index}" 2>/dev/null | grep -q "^${pane_id}$"; then
            filename=$(basename "$identity_file")
            echo "Archiving stale identity: $filename (pane $pane_id does not exist)"
            mv "$identity_file" "$ARCHIVE_DIR/"
        fi
    fi
done

# Cleanup stale agent-name files
for agent_name_file in "$PIDS_DIR/"*.agent-name; do
    [ -f "$agent_name_file" ] || continue

    filename=$(basename "$agent_name_file" .agent-name)
    pane_id=$(echo "$filename" | sed 's/\(.*\)-/\1./; s/\(.*\)-/\1:/')

    if ! tmux list-panes -a -F "#{session_name}:#{window_index}.#{pane_index}" 2>/dev/null | grep -q "^${pane_id}$"; then
        echo "Archiving stale agent-name: $(basename $agent_name_file) (pane $pane_id does not exist)"
        mv "$agent_name_file" "$ARCHIVE_DIR/"
    fi
done

# Cleanup stale lock files
find "$PANES_DIR" -name '*.lock' -type f -exec mv {} "$ARCHIVE_DIR/" \; 2>/dev/null

# --- END ---
SCRIPT_EOF

# Patch in the actual paths
sed -i '' "s|MOCK_DIR|$TMPDIR|g" "$TMPDIR/test-discover-all.sh"
sed -i '' "s|TEST_PROJECT_DIR|$TEST_PROJECT|g" "$TMPDIR/test-discover-all.sh"
chmod +x "$TMPDIR/test-discover-all.sh"

# Run the test
OUTPUT=$("$TMPDIR/test-discover-all.sh" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    pass "Cleanup script ran successfully (exit 0)"
else
    fail "Cleanup script should exit 0" "exit code: $EXIT_CODE, output: $OUTPUT"
fi

# ---- Verify: active identity files preserved ----

echo ""
echo "=== Test: --all mode preserves active identity files ==="

if [ -f "$TEST_PROJECT/panes/agent-flywheel-integration-1-1.identity" ]; then
    pass "Preserved active identity: agent-flywheel-integration-1-1"
else
    fail "Should preserve agent-flywheel-integration-1-1.identity (pane is active)"
fi

if [ -f "$TEST_PROJECT/panes/besteman-land-cattle-1-2.identity" ]; then
    pass "Preserved active identity: besteman-land-cattle-1-2"
else
    fail "Should preserve besteman-land-cattle-1-2.identity (pane is active)"
fi

# ---- Verify: stale identity files archived ----

echo ""
echo "=== Test: --all mode archives stale identity files ==="

if [ ! -f "$TEST_PROJECT/panes/besteman-land-cattle-1-3.identity" ] && \
   [ -f "$TEST_PROJECT/archive/panes/besteman-land-cattle-1-3.identity" ]; then
    pass "Archived stale identity: besteman-land-cattle-1-3"
else
    fail "Should archive besteman-land-cattle-1-3.identity (pane does not exist)" \
        "in panes: $(ls "$TEST_PROJECT/panes/" 2>/dev/null), in archive: $(ls "$TEST_PROJECT/archive/panes/" 2>/dev/null)"
fi

if [ ! -f "$TEST_PROJECT/panes/old-session-1-4.identity" ] && \
   [ -f "$TEST_PROJECT/archive/panes/old-session-1-4.identity" ]; then
    pass "Archived stale identity: old-session-1-4"
else
    fail "Should archive old-session-1-4.identity (pane does not exist)" \
        "in panes: $(ls "$TEST_PROJECT/panes/" 2>/dev/null), in archive: $(ls "$TEST_PROJECT/archive/panes/" 2>/dev/null)"
fi

# ---- Verify: stale identity file content is preserved in archive ----

echo ""
echo "=== Test: --all mode preserves content of archived files ==="

ARCHIVED_AGENT=$(jq -r '.agent_mail_name' "$TEST_PROJECT/archive/panes/besteman-land-cattle-1-3.identity" 2>/dev/null)
if [ "$ARCHIVED_AGENT" = "IvoryMarsh" ]; then
    pass "Archived identity content preserved (IvoryMarsh)"
else
    fail "Archived identity should preserve agent_mail_name" "got: $ARCHIVED_AGENT"
fi

# ---- Verify: active agent-name files preserved ----

echo ""
echo "=== Test: --all mode preserves active agent-name files ==="

if [ -f "$TEST_PROJECT/pids/agent-flywheel-integration-1-1.agent-name" ]; then
    pass "Preserved active agent-name: agent-flywheel-integration-1-1"
else
    fail "Should preserve agent-flywheel-integration-1-1.agent-name (pane is active)"
fi

if [ -f "$TEST_PROJECT/pids/besteman-land-cattle-1-2.agent-name" ]; then
    pass "Preserved active agent-name: besteman-land-cattle-1-2"
else
    fail "Should preserve besteman-land-cattle-1-2.agent-name (pane is active)"
fi

# ---- Verify: stale agent-name files archived ----

echo ""
echo "=== Test: --all mode archives stale agent-name files ==="

if [ ! -f "$TEST_PROJECT/pids/besteman-land-cattle-1-3.agent-name" ] && \
   [ -f "$TEST_PROJECT/archive/panes/besteman-land-cattle-1-3.agent-name" ]; then
    pass "Archived stale agent-name: besteman-land-cattle-1-3"
else
    fail "Should archive besteman-land-cattle-1-3.agent-name (pane does not exist)" \
        "in pids: $(ls "$TEST_PROJECT/pids/" 2>/dev/null), in archive: $(ls "$TEST_PROJECT/archive/panes/" 2>/dev/null)"
fi

if [ ! -f "$TEST_PROJECT/pids/old-session-1-4.agent-name" ] && \
   [ -f "$TEST_PROJECT/archive/panes/old-session-1-4.agent-name" ]; then
    pass "Archived stale agent-name: old-session-1-4"
else
    fail "Should archive old-session-1-4.agent-name (pane does not exist)" \
        "in pids: $(ls "$TEST_PROJECT/pids/" 2>/dev/null), in archive: $(ls "$TEST_PROJECT/archive/panes/" 2>/dev/null)"
fi

# ---- Verify: lock files cleaned up ----

echo ""
echo "=== Test: --all mode archives lock files ==="

if [ ! -f "$TEST_PROJECT/panes/some-stale.lock" ] && \
   [ -f "$TEST_PROJECT/archive/panes/some-stale.lock" ]; then
    pass "Archived lock file: some-stale.lock"
else
    fail "Should archive lock files" \
        "in panes: $(ls "$TEST_PROJECT/panes/"*.lock 2>/dev/null || echo 'none'), in archive: $(ls "$TEST_PROJECT/archive/panes/"*.lock 2>/dev/null || echo 'none')"
fi


# ============================================================
# Section 3: edge case - identity file with no pane field
# ============================================================

echo ""
echo "=== Test: --all mode handles identity file with no pane field ==="

# Reset test environment
rm -rf "$TEST_PROJECT/panes/"*.identity "$TEST_PROJECT/archive/panes/"*

# Create identity file with no pane field
echo '{"name":"Orphan","type":"terminal"}' > "$TEST_PROJECT/panes/orphan-1-1.identity"

OUTPUT=$("$TMPDIR/test-discover-all.sh" 2>&1)

# File should remain in panes (no pane field means we can't check tmux, so skip it)
if [ -f "$TEST_PROJECT/panes/orphan-1-1.identity" ]; then
    pass "Identity file with no pane field left in place (not archived)"
else
    fail "Identity with no pane field should not be archived" \
        "in archive: $(ls "$TEST_PROJECT/archive/panes/" 2>/dev/null)"
fi


# ============================================================
# Section 4: edge case - empty panes/pids directories
# ============================================================

echo ""
echo "=== Test: --all mode handles empty directories ==="

rm -rf "$TEST_PROJECT/panes/"*.identity "$TEST_PROJECT/pids/"*.agent-name "$TEST_PROJECT/archive/panes/"*

OUTPUT=$("$TMPDIR/test-discover-all.sh" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    pass "Handles empty panes/pids directories without error"
else
    fail "Should handle empty directories gracefully" "exit: $EXIT_CODE, output: $OUTPUT"
fi


# ============================================================
# Section 5: sed pattern correctness - the old (buggy) pattern
# ============================================================
# Verify that the OLD pattern (first two hyphens) would fail on
# multi-hyphen session names, confirming the fix is necessary.

echo ""
echo "=== Test: old sed pattern fails on multi-hyphen names (regression check) ==="

# Old pattern: sed 's/-/:/; s/-/./' (replaces first two hyphens)
OLD_RESULT=$(echo "agent-flywheel-integration-1-1" | sed 's/-/:/; s/-/./')

if [ "$OLD_RESULT" != "agent-flywheel-integration:1.1" ]; then
    pass "Old pattern produces wrong result: '$OLD_RESULT' (confirms fix was needed)"
else
    fail "Old pattern should NOT produce correct result for multi-hyphen names"
fi

# New pattern: sed 's/\(.*\)-/\1./; s/\(.*\)-/\1:/' (replaces last two hyphens)
NEW_RESULT=$(echo "agent-flywheel-integration-1-1" | sed 's/\(.*\)-/\1./; s/\(.*\)-/\1:/')

if [ "$NEW_RESULT" = "agent-flywheel-integration:1.1" ]; then
    pass "New pattern produces correct result: '$NEW_RESULT'"
else
    fail "New pattern should produce correct result" "got: $NEW_RESULT"
fi


# ============================================================
# Results
# ============================================================

echo ""
echo "=============================="
echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
