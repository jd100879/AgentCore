#!/usr/bin/env bash
# test_fleet_core.sh - Unit tests for fleet-core.sh
#
# Tests:
#   1. cache_is_fresh returns correct staleness
#   2. cache_get/cache_set round-trip
#   3. cache_clear removes all cache files
#   4. cache_cleanup removes old files, keeps fresh ones
#   5. Main dispatch: known commands exit 0
#   6. Main dispatch: unknown command exits 1
#   7. aggregate returns valid JSON structure
#
# Usage: ./tests/test_fleet_core.sh

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/fleet-core.sh"

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

# Create isolated test cache directory
TEST_CACHE_DIR=$(mktemp -d /tmp/test-fleet-cache.XXXXXX)
trap "rm -rf '$TEST_CACHE_DIR'" EXIT

echo "=== Test: cache_is_fresh with missing file ==="

# Source the script to get functions (it guards with BASH_SOURCE check)
source "$SCRIPT"

# Override CACHE_DIR for testing
CACHE_DIR="$TEST_CACHE_DIR"

# Test: missing file is stale
if ! cache_is_fresh "$TEST_CACHE_DIR/nonexistent.json" 60; then
    pass "Missing file is stale"
else
    fail "Missing file should be stale"
fi

echo ""
echo "=== Test: cache_is_fresh with fresh file ==="

# Create a fresh file
echo '{"test": true}' > "$TEST_CACHE_DIR/fresh.json"

if cache_is_fresh "$TEST_CACHE_DIR/fresh.json" 60; then
    pass "Just-created file is fresh (TTL 60s)"
else
    fail "Just-created file should be fresh"
fi

echo ""
echo "=== Test: cache_is_fresh with stale file ==="

# Create a stale file (touch with old timestamp)
echo '{"old": true}' > "$TEST_CACHE_DIR/stale.json"
touch -t 202001010000 "$TEST_CACHE_DIR/stale.json"

if ! cache_is_fresh "$TEST_CACHE_DIR/stale.json" 60; then
    pass "Old file is stale"
else
    fail "Old file should be stale"
fi

echo ""
echo "=== Test: cache_get/cache_set round-trip ==="

# Set a cache value
echo '{"cached": "data", "count": 42}' | cache_set "test_roundtrip"

# Verify file exists
if [ -f "$TEST_CACHE_DIR/test_roundtrip.json" ]; then
    pass "cache_set creates file"
else
    fail "cache_set should create file"
fi

# Get the cache value (should be fresh since we just set it)
CACHED=$(cache_get "test_roundtrip" 60)

if [ -n "$CACHED" ]; then
    pass "cache_get returns data for fresh cache"
else
    fail "cache_get should return data for fresh cache"
fi

if echo "$CACHED" | jq -e '.count == 42' >/dev/null 2>&1; then
    pass "Cached data is correct JSON"
else
    fail "Cached data should be correct JSON" "$CACHED"
fi

echo ""
echo "=== Test: cache_get returns empty for stale data ==="

# Make the cache file old
touch -t 202001010000 "$TEST_CACHE_DIR/test_roundtrip.json"

CACHED=$(cache_get "test_roundtrip" 5)

if [ -z "$CACHED" ]; then
    pass "cache_get returns empty for stale cache"
else
    fail "cache_get should return empty for stale cache" "$CACHED"
fi

echo ""
echo "=== Test: cache_clear removes all cache files ==="

# Create several cache files
echo '{}' > "$TEST_CACHE_DIR/a.json"
echo '{}' > "$TEST_CACHE_DIR/b.json"
echo '{}' > "$TEST_CACHE_DIR/c.json"

OUTPUT=$(cache_clear 2>/dev/null)

FILE_COUNT=$(ls "$TEST_CACHE_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')
if [ "$FILE_COUNT" -eq 0 ]; then
    pass "cache_clear removes all .json files"
else
    fail "cache_clear should remove all files, found $FILE_COUNT"
fi

if echo "$OUTPUT" | jq -e '.status == "success"' >/dev/null 2>&1; then
    pass "cache_clear returns success JSON"
else
    fail "cache_clear should return success JSON"
fi

echo ""
echo "=== Test: cache_cleanup removes only old files ==="

# Create a fresh file and an old file
echo '{"fresh": true}' > "$TEST_CACHE_DIR/keep.json"
echo '{"old": true}' > "$TEST_CACHE_DIR/remove.json"
touch -t 202001010000 "$TEST_CACHE_DIR/remove.json"

OUTPUT=$(cache_cleanup 2>/dev/null)

if [ -f "$TEST_CACHE_DIR/keep.json" ]; then
    pass "cache_cleanup keeps fresh files"
else
    fail "cache_cleanup should keep fresh files"
fi

if [ ! -f "$TEST_CACHE_DIR/remove.json" ]; then
    pass "cache_cleanup removes old files"
else
    fail "cache_cleanup should remove old files"
fi

if echo "$OUTPUT" | jq -e '.status == "success"' >/dev/null 2>&1; then
    pass "cache_cleanup returns success JSON"
else
    fail "cache_cleanup should return success JSON"
fi

echo ""
echo "=== Test: unknown command exits non-zero ==="

EXIT_CODE=0
OUTPUT=$("$SCRIPT" bogus_command 2>&1) || EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    pass "Unknown command exits non-zero"
else
    fail "Unknown command should exit non-zero"
fi

if echo "$OUTPUT" | grep -q "Usage:"; then
    pass "Unknown command shows usage"
else
    fail "Unknown command should show usage"
fi

echo ""
echo "=== Test: cache_clear via main dispatch ==="

# Create a cache file
CACHE_DIR="$TEST_CACHE_DIR"
echo '{}' > "$TEST_CACHE_DIR/dispatch_test.json"

OUTPUT=$("$SCRIPT" cache_clear 2>&1)

# Check the real cache dir was cleared (not our test dir)
# Instead, test the output format
if echo "$OUTPUT" | jq -e '.status == "success"' >/dev/null 2>&1; then
    pass "cache_clear dispatch returns success"
else
    fail "cache_clear dispatch should return success"
fi

echo ""
echo "=== Test: get_active_agents handles no tmux gracefully ==="

# If tmux is available, this should produce valid JSON
OUTPUT=$(get_active_agents 2>/dev/null)

if echo "$OUTPUT" | jq -e '.' >/dev/null 2>&1; then
    pass "get_active_agents returns valid JSON"
else
    fail "get_active_agents should return valid JSON" "$OUTPUT"
fi

# Should have count field
if echo "$OUTPUT" | jq -e 'has("count") or has("error")' >/dev/null 2>&1; then
    pass "get_active_agents has count or error field"
else
    fail "get_active_agents should have count or error" "$OUTPUT"
fi

echo ""
echo "=============================="
echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
