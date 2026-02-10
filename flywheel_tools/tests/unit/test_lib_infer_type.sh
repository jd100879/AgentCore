#!/usr/bin/env bash
# test_lib_infer_type.sh - Unit tests for lib-infer-type.sh infer_agent_type()
#
# Tests the keyword-based type inference logic used by br-create.sh
# to auto-classify beads into: general, backend, frontend, devops, docs, qa
#
# Usage: ./tests/test_lib_infer_type.sh

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

# Source the library
source "$PROJECT_ROOT/scripts/lib-infer-type.sh"

# Helper: assert infer_agent_type returns expected type
assert_type() {
    local expected="$1"
    local title="$2"
    local description="${3:-}"
    local labels="${4:-}"

    local actual
    actual=$(infer_agent_type "$title" "$description" "$labels")

    if [ "$actual" = "$expected" ]; then
        pass "\"$title\" → $expected"
    else
        fail "\"$title\" → expected '$expected', got '$actual'" "desc='$description' labels='$labels'"
    fi
}

echo "=== Label-based inference (highest priority) ==="

assert_type "frontend" "Fix something" "" "frontend"
assert_type "frontend" "Fix something" "" "ui"
assert_type "backend"  "Fix something" "" "backend"
assert_type "backend"  "Fix something" "" "api"
assert_type "devops"   "Fix something" "" "devops"
assert_type "devops"   "Fix something" "" "infrastructure"
assert_type "docs"     "Fix something" "" "docs"
assert_type "docs"     "Fix something" "" "documentation"
assert_type "qa"       "Fix something" "" "qa"
assert_type "qa"       "Fix something" "" "testing"

echo ""
echo "=== Label overrides keyword inference ==="

# Title says "test" (→ qa), but label says "backend" → backend wins
assert_type "backend" "Add test coverage" "" "backend"
# Title says "api" (→ backend), but label says "frontend" → frontend wins
assert_type "frontend" "Update API docs" "" "frontend"
# Title says "deploy" (→ devops), but label says "qa" → qa wins
assert_type "qa" "Deploy test harness" "" "qa"

echo ""
echo "=== QA keyword inference ==="

assert_type "qa" "Add test coverage" "" ""
assert_type "qa" "Improve test coverage for login" "" ""
assert_type "qa" "Run e2e tests" "" ""
assert_type "qa" "Add lint rules for imports" "" ""
assert_type "qa" "Create benchmark suite" "" ""
assert_type "qa" "Fix coverage reporting" "" ""

echo ""
echo "=== Docs keyword inference ==="

assert_type "docs" "Update README" "" ""
assert_type "docs" "Write guide for new agents" "" ""
assert_type "docs" "Add tutorial for beads" "" ""
assert_type "docs" "Update changelog for v2" "" ""
assert_type "docs" "Document the API" "" ""
assert_type "docs" "Write specification for auth" "" ""
assert_type "docs" "Add openapi spec" "" ""

echo ""
echo "=== DevOps keyword inference ==="

assert_type "devops" "Fix Docker build" "" ""
assert_type "devops" "Update CI/CD pipeline" "" ""
assert_type "devops" "Deploy to staging" "" ""
assert_type "devops" "Add monitoring dashboard" "" ""
assert_type "devops" "Configure nginx reverse proxy" "" ""
assert_type "devops" "Update terraform modules" "" ""
assert_type "devops" "Create helm chart" "" ""
assert_type "devops" "Fix kubernetes pod restart" "" ""

echo ""
echo "=== Frontend keyword inference ==="

assert_type "frontend" "Fix CSS alignment issue" "" ""
assert_type "frontend" "Create button component" "" ""
assert_type "frontend" "Improve responsive layout" "" ""
assert_type "frontend" "Add React context provider" "" ""
assert_type "frontend" "Fix Vue rendering bug" "" ""
assert_type "frontend" "Update page styles" "" ""
assert_type "frontend" "Build new form component" "" ""

echo ""
echo "=== Backend keyword inference ==="

assert_type "backend" "Add new API endpoint" "" ""
assert_type "backend" "Fix database connection pool" "" ""
assert_type "backend" "Create migration for users table" "" ""
assert_type "backend" "Update schema validation" "" ""
assert_type "backend" "Optimize SQL queries" "" ""
assert_type "backend" "Add auth middleware" "" ""
assert_type "backend" "Fix server startup crash" "" ""

echo ""
echo "=== General (default) inference ==="

assert_type "general" "Fix typo in variable name" "" ""
assert_type "general" "Refactor utility function" "" ""
assert_type "general" "Clean up old imports" "" ""
assert_type "general" "Bump version number" "" ""

echo ""
echo "=== Description-based inference ==="

# Title is generic but description has keywords
assert_type "backend" "Fix the issue" "The API endpoint returns 500" ""
assert_type "frontend" "Update the component" "The CSS layout breaks on mobile" ""
assert_type "devops" "Fix the build" "Docker container fails to start" ""
assert_type "qa" "Improve reliability" "Add e2e test for the workflow" ""

echo ""
echo "=== Case insensitivity ==="

assert_type "backend"  "Fix API Endpoint" "" ""
assert_type "frontend" "Update CSS Layout" "" ""
assert_type "devops"   "Docker Build Fix" "" ""
assert_type "qa"       "Add TEST Coverage" "" ""
assert_type "backend"  "FIX DATABASE ISSUE" "" ""

echo ""
echo "=== Priority order: QA > docs > devops > frontend > backend ==="

# "test" + "api" → qa wins (checked before backend)
assert_type "qa" "Test the API endpoint" "" ""
# "document" + "api" → docs wins (checked before backend)
assert_type "docs" "Document API endpoints" "" ""
# "deploy" + "css" → devops wins (checked before frontend)
assert_type "devops" "Deploy CSS pipeline" "" ""

echo ""
echo "=============================="
echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
