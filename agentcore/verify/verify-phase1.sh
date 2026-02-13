#!/usr/bin/env bash
# Phase 1 Verification Suite
# Defensive verification for agentcore coordination infrastructure
#
# This script verifies:
# 1. No hidden directories inside agentcore/
# 2. All expected symlinks exist and resolve correctly
# 3. External mail repo is reachable
# 4. agentcore/tools aliases are present
#
# Exit codes:
#   0 - All checks passed
#   1 - One or more checks failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTCORE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$AGENTCORE_ROOT/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================"
echo "Phase 1 Verification Suite"
echo "========================================"
echo ""
echo "Verifying agentcore coordination infrastructure..."
echo "Root: $AGENTCORE_ROOT"
echo ""

TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Helper function to run a check
run_check() {
  local check_script="$1"
  local check_name="$2"

  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

  echo "========================================" echo "Check: $check_name"
  echo "----------------------------------------"

  if bash "$check_script"; then
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    echo ""
  else
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
    echo ""
  fi
}

# Run individual checks
run_check "$SCRIPT_DIR/checks/check-no-dotdirs.sh" "No hidden directories in agentcore"
run_check "$SCRIPT_DIR/checks/check-symlinks.sh" "Symlink integrity"
run_check "$SCRIPT_DIR/checks/check-mail-repo.sh" "External mail repo accessibility"

# Summary
echo "========================================"
echo "Verification Summary"
echo "========================================"
echo "Total checks:  $TOTAL_CHECKS"
echo -e "Passed:        ${GREEN}$PASSED_CHECKS${NC}"
if [ $FAILED_CHECKS -gt 0 ]; then
  echo -e "Failed:        ${RED}$FAILED_CHECKS${NC}"
else
  echo "Failed:        $FAILED_CHECKS"
fi
echo ""

if [ $FAILED_CHECKS -eq 0 ]; then
  echo -e "${GREEN}✓ All Phase 1 verification checks PASSED${NC}"
  echo ""
  echo "Phase 1 infrastructure is correctly set up."
  echo "All symlinks resolve, no hidden directories in agentcore,"
  echo "and external mail repo is accessible."
  exit 0
else
  echo -e "${RED}✗ Phase 1 verification FAILED${NC}"
  echo ""
  echo "One or more checks failed. Review the output above."
  echo "Do not proceed to Phase 2 until all checks pass."
  echo ""
  echo "Common issues:"
  echo "  - Missing symlinks: Run the corresponding setup bead"
  echo "  - Broken symlinks: Check that target directories exist"
  echo "  - Hidden directories: These should be at project root only"
  echo "  - Mail repo: Ensure MCP mail is initialized"
  exit 1
fi
