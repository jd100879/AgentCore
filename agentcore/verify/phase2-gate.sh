#!/usr/bin/env bash
# Phase 2 Verification Gate - PRODUCTION-GRADE TESTING
# Validates Phase 2 completeness with comprehensive checks
#
# This script verifies:
# 1. Wrapper completeness (all coordination scripts have wrappers)
# 2. Symlink integrity + executability (all agentcore/tools/* point to valid, executable targets)
# 3. Mail pointer exists and is valid
# 4. No git case collision (capital AgentCore/ vs lowercase agentcore/)
# 5. Comprehensive functional tests (ALL 7 tools work from 4 CWDs including deep nested)
#
# Exit codes:
#   0 - All checks passed
#   1 - One or more checks failed
#
# This is a READ-ONLY gate - it does not fix issues, only reports them

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
echo "Phase 2 Verification Gate (PRODUCTION)"
echo "========================================"
echo ""
echo "Verifying Phase 2 infrastructure with production-grade testing..."
echo "Root: $AGENTCORE_ROOT"
echo ""

FAILED=0

#
# Check 1: Wrapper completeness
#
echo "========================================"
echo "Check 1: Wrapper Completeness"
echo "----------------------------------------"
echo "Verifying all coordination scripts have wrappers in agentcore/tools/"
echo ""

# Define coordination scripts that should have wrappers
COORDINATION_SCRIPTS=(
  "agent-control.sh"
  "agent-mail-helper.sh"
  "agent-registry.sh"
  "auto-register-agent.sh"
  "mail-monitor-ctl.sh"
  "monitor-agent-mail-to-terminal.sh"
  "start-multi-agent-session.sh"
)

WRAPPER_CHECK_FAILED=0
for script in "${COORDINATION_SCRIPTS[@]}"; do
  wrapper_path="$AGENTCORE_ROOT/tools/$script"

  if [ ! -L "$wrapper_path" ]; then
    echo -e "${RED}✗ FAIL${NC}: Missing wrapper for $script"
    echo "  Expected wrapper at: agentcore/tools/$script"
    echo "  Action: Create symlink: ln -s ../../scripts/$script agentcore/tools/$script"
    WRAPPER_CHECK_FAILED=1
  else
    # Verify symlink points to correct target
    target=$(readlink "$wrapper_path")
    expected_target="../../scripts/$script"

    if [ "$target" != "$expected_target" ]; then
      echo -e "${YELLOW}⚠ WARNING${NC}: Wrapper for $script has unexpected target"
      echo "  Expected: $expected_target"
      echo "  Actual:   $target"
      # Don't fail, just warn - as long as it resolves
    fi

    # Verify symlink resolves
    if [ ! -e "$wrapper_path" ]; then
      echo -e "${RED}✗ FAIL${NC}: Broken wrapper for $script"
      echo "  Wrapper exists but target does not resolve"
      echo "  Symlink: $wrapper_path -> $target"
      echo "  Action: Check if scripts/$script exists"
      WRAPPER_CHECK_FAILED=1
    else
      echo -e "${GREEN}✓${NC} $script"
    fi
  fi
done

echo ""
if [ $WRAPPER_CHECK_FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ PASS${NC}: All coordination scripts have valid wrappers"
else
  echo -e "${RED}✗ FAIL${NC}: One or more wrappers missing or broken"
  FAILED=1
fi
echo ""

#
# Check 2: Symlink integrity + executability
#
echo "========================================"
echo "Check 2: Symlink Integrity + Executability"
echo "----------------------------------------"
echo "Verifying all agentcore/tools/* symlinks are valid and executable"
echo ""

SYMLINK_CHECK_FAILED=0
if [ -d "$AGENTCORE_ROOT/tools" ]; then
  for link_path in "$AGENTCORE_ROOT/tools"/*; do
    if [ -L "$link_path" ]; then
      link_name=$(basename "$link_path")

      if [ ! -e "$link_path" ]; then
        echo -e "${RED}✗ FAIL${NC}: Broken symlink: tools/$link_name"
        target=$(readlink "$link_path")
        echo "  Points to: $target"
        echo "  Action: Fix or remove broken symlink"
        SYMLINK_CHECK_FAILED=1
      elif [ ! -x "$link_path" ]; then
        echo -e "${RED}✗ FAIL${NC}: Not executable: tools/$link_name"
        echo "  Action: chmod +x scripts/$link_name"
        SYMLINK_CHECK_FAILED=1
      else
        echo -e "${GREEN}✓${NC} tools/$link_name (executable)"
      fi
    fi
  done
else
  echo -e "${RED}✗ FAIL${NC}: agentcore/tools/ directory does not exist"
  echo "  Action: Create agentcore/tools directory"
  SYMLINK_CHECK_FAILED=1
fi

echo ""
if [ $SYMLINK_CHECK_FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ PASS${NC}: All symlinks in agentcore/tools/ are valid and executable"
else
  echo -e "${RED}✗ FAIL${NC}: One or more symlinks are broken or not executable"
  FAILED=1
fi
echo ""

#
# Check 3: Mail pointer exists and is valid
#
echo "========================================"
echo "Check 3: Mail Pointer"
echo "----------------------------------------"
echo "Verifying agentcore/mail/repo-location.txt exists and is valid"
echo ""

MAIL_CHECK_FAILED=0
mail_pointer="$AGENTCORE_ROOT/mail/repo-location.txt"

if [ ! -f "$mail_pointer" ]; then
  echo -e "${RED}✗ FAIL${NC}: Mail pointer file does not exist"
  echo "  Expected: agentcore/mail/repo-location.txt"
  echo "  Action: Create file with path to mail repo"
  MAIL_CHECK_FAILED=1
else
  mail_repo_path=$(cat "$mail_pointer")

  if [ -z "$mail_repo_path" ]; then
    echo -e "${RED}✗ FAIL${NC}: Mail pointer file is empty"
    echo "  File: $mail_pointer"
    echo "  Action: Add mail repo path to file"
    MAIL_CHECK_FAILED=1
  elif [ ! -d "$mail_repo_path" ]; then
    echo -e "${RED}✗ FAIL${NC}: Mail repo path does not exist"
    echo "  Pointer file: $mail_pointer"
    echo "  Points to: $mail_repo_path"
    echo "  Action: Ensure mail repo is initialized or update pointer"
    MAIL_CHECK_FAILED=1
  else
    echo -e "${GREEN}✓${NC} Mail pointer exists and points to valid directory"
    echo "  Location: $mail_repo_path"
  fi
fi

echo ""
if [ $MAIL_CHECK_FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ PASS${NC}: Mail pointer is valid"
else
  echo -e "${RED}✗ FAIL${NC}: Mail pointer check failed"
  FAILED=1
fi
echo ""

#
# Check 4: Git case collision check
#
echo "========================================"
echo "Check 4: Git Case Collision"
echo "----------------------------------------"
echo "Checking for capital 'AgentCore/' in git (should not exist)"
echo ""

CASE_CHECK_FAILED=0
cd "$PROJECT_ROOT"

# Use git ls-files to check for case collision (capital A vs lowercase a)
capital_files=$(git ls-files | grep -E '^AgentCore/' || true)

if [ -n "$capital_files" ]; then
  echo -e "${RED}✗ FAIL${NC}: Found files under capital 'AgentCore/' in git"
  echo ""
  echo "Files found:"
  echo "$capital_files" | while read -r file; do
    echo "  - $file"
  done
  echo ""
  echo "This creates case collision on case-insensitive filesystems (macOS)."
  echo "Action: Remove these files from git:"
  echo "  git rm -r AgentCore/"
  echo "  git commit -m '[phase2] Remove case-colliding AgentCore/ directory'"
  CASE_CHECK_FAILED=1
else
  echo -e "${GREEN}✓${NC} No capital 'AgentCore/' found in git"
  echo "  Case collision check passed"
fi

echo ""
if [ $CASE_CHECK_FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ PASS${NC}: No git case collision detected"
else
  echo -e "${RED}✗ FAIL${NC}: Git case collision detected"
  FAILED=1
fi
echo ""

#
# Check 5: Comprehensive Functional Smoke Tests
#
echo "========================================"
echo "Check 5: Comprehensive Functional Smoke Tests"
echo "----------------------------------------"
echo "Testing ALL coordination tools from multiple CWDs (including deep nested)"
echo ""

FUNCTIONAL_CHECK_FAILED=0

# Define test commands for each coordination script
declare -A TOOL_TEST_COMMANDS
TOOL_TEST_COMMANDS["agent-control.sh"]="--help"
TOOL_TEST_COMMANDS["agent-mail-helper.sh"]="--help"
TOOL_TEST_COMMANDS["agent-registry.sh"]="list"
TOOL_TEST_COMMANDS["auto-register-agent.sh"]="--help"
TOOL_TEST_COMMANDS["mail-monitor-ctl.sh"]="--help"
TOOL_TEST_COMMANDS["monitor-agent-mail-to-terminal.sh"]="--help"
TOOL_TEST_COMMANDS["start-multi-agent-session.sh"]="--help"

# Test CWDs
TEST_CWDS=(
  "/"                           # Hostile: root
  "/tmp"                        # Hostile: temp dir
  "$PROJECT_ROOT"               # Friendly: repo root
)

# Create deep nested CWD for testing
DEEP_NESTED_DIR="/tmp/phase2-test/a/b/c/d/e"
mkdir -p "$DEEP_NESTED_DIR"
TEST_CWDS+=("$DEEP_NESTED_DIR")

echo "Testing from 4 different working directories:"
echo "  - / (root)"
echo "  - /tmp (temp)"
echo "  - $PROJECT_ROOT (repo root)"
echo "  - $DEEP_NESTED_DIR (deep nested)"
echo ""

# Test each tool from each CWD
for script in "${COORDINATION_SCRIPTS[@]}"; do
  test_cmd="${TOOL_TEST_COMMANDS[$script]}"
  tool_failed=0

  echo "Testing $script..."

  for cwd in "${TEST_CWDS[@]}"; do
    cwd_label="$cwd"
    if [ "$cwd" = "$PROJECT_ROOT" ]; then
      cwd_label="repo-root"
    elif [ "$cwd" = "$DEEP_NESTED_DIR" ]; then
      cwd_label="deep-nested"
    fi

    # Capture exit code properly
    (cd "$cwd" && "$AGENTCORE_ROOT/tools/$script" $test_cmd >/dev/null 2>&1)
    exit_code=$?

    if [ $exit_code -eq 0 ]; then
      echo -e "  ${GREEN}✓${NC} from $cwd_label"
    else
      echo -e "  ${RED}✗ FAIL${NC}: from $cwd_label (exit code: $exit_code)"
      echo "    Command: (cd $cwd && $AGENTCORE_ROOT/tools/$script $test_cmd)"
      tool_failed=1
      FUNCTIONAL_CHECK_FAILED=1
    fi
  done

  if [ $tool_failed -eq 0 ]; then
    echo -e "${GREEN}✓${NC} $script works from all CWDs"
  fi
  echo ""
done

# Cleanup deep nested test directory
rm -rf /tmp/phase2-test

echo ""
if [ $FUNCTIONAL_CHECK_FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ PASS${NC}: Comprehensive functional smoke tests passed"
  echo "  All 7 coordination tools work from all 4 tested CWDs"
  echo "  Including deep nested path: $DEEP_NESTED_DIR"
else
  echo -e "${RED}✗ FAIL${NC}: One or more functional tests failed"
  echo "  Tools must work when invoked via canonical paths from any CWD"
  FAILED=1
fi
echo ""

#
# Final Summary
#
echo "========================================"
echo "Phase 2 Verification Summary (PRODUCTION)"
echo "========================================"
echo ""

if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ All Phase 2 verification checks PASSED${NC}"
  echo ""
  echo "Phase 2 infrastructure is production-ready:"
  echo "  - All coordination scripts have valid wrappers"
  echo "  - All symlinks are valid and executable"
  echo "  - Mail pointer exists and is valid"
  echo "  - No git case collision detected"
  echo "  - All 7 tools tested from 4 CWDs (including deep nested)"
  echo "  - Production-grade test coverage achieved"
  echo ""
  echo "Phase 2 gate: OPEN - Ready to proceed"
  exit 0
else
  echo -e "${RED}✗ Phase 2 verification FAILED${NC}"
  echo ""
  echo "One or more checks failed. Review the output above."
  echo "Do not proceed to Phase 3 until all checks pass."
  echo ""
  echo "This gate is READ-ONLY - it does not fix issues."
  echo "Follow the action items listed above to resolve failures."
  echo ""
  echo "Phase 2 gate: CLOSED - Fix issues before proceeding"
  exit 1
fi
