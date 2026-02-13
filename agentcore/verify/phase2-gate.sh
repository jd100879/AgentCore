#!/usr/bin/env bash
# Phase 2 Verification Gate
# Validates Phase 2 completeness with git-aware checks
#
# This script verifies:
# 1. Wrapper completeness (all coordination scripts have wrappers)
# 2. Symlink integrity (all agentcore/tools/* point to valid targets)
# 3. Mail pointer exists and is valid
# 4. No git case collision (capital AgentCore/ vs lowercase agentcore/)
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
echo "Phase 2 Verification Gate"
echo "========================================"
echo ""
echo "Verifying Phase 2 infrastructure completeness..."
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
# Check 2: Symlink integrity
#
echo "========================================"
echo "Check 2: Symlink Integrity"
echo "----------------------------------------"
echo "Verifying all agentcore/tools/* symlinks are valid"
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
      else
        echo -e "${GREEN}✓${NC} tools/$link_name"
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
  echo -e "${GREEN}✓ PASS${NC}: All symlinks in agentcore/tools/ are valid"
else
  echo -e "${RED}✗ FAIL${NC}: One or more symlinks are broken"
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
# Final Summary
#
echo "========================================"
echo "Phase 2 Verification Summary"
echo "========================================"
echo ""

if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ All Phase 2 verification checks PASSED${NC}"
  echo ""
  echo "Phase 2 infrastructure is complete:"
  echo "  - All coordination scripts have wrappers"
  echo "  - All symlinks in agentcore/tools/ are valid"
  echo "  - Mail pointer exists and is valid"
  echo "  - No git case collision detected"
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
