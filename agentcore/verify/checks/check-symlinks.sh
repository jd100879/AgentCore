#!/usr/bin/env bash
# Verify all expected symlinks exist and resolve correctly
# Phase 1: Outward symlinks (agentcore points to existing locations)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTCORE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_ROOT="$(cd "$AGENTCORE_ROOT/.." && pwd)"

echo "Checking symlinks in agentcore/..."

FAILED=0

# Helper function to check a symlink
check_symlink() {
  local link_path="$1"
  local expected_target="$2"
  local description="$3"

  local full_link_path="$AGENTCORE_ROOT/$link_path"

  # Check if symlink exists
  if [ ! -L "$full_link_path" ]; then
    echo "❌ FAIL: $description - Not a symlink: $link_path"
    FAILED=1
    return
  fi

  # Check if symlink resolves
  if [ ! -e "$full_link_path" ]; then
    echo "❌ FAIL: $description - Broken symlink: $link_path"
    FAILED=1
    return
  fi

  # Get actual target
  local actual_target=$(readlink "$full_link_path")

  # Check if target matches expected (allowing for absolute vs relative)
  if [ "$actual_target" != "$expected_target" ]; then
    # Also check if they resolve to the same location
    local actual_resolved=$(cd "$(dirname "$full_link_path")" && cd "$(dirname "$actual_target")" && pwd)/$(basename "$actual_target")
    local expected_resolved=$(cd "$(dirname "$full_link_path")" && cd "$(dirname "$expected_target")" && pwd)/$(basename "$expected_target")

    if [ "$actual_resolved" != "$expected_resolved" ]; then
      echo "❌ FAIL: $description - Wrong target"
      echo "   Expected: $expected_target"
      echo "   Actual:   $actual_target"
      FAILED=1
      return
    fi
  fi

  echo "✓ $description"
}

echo ""
echo "Config symlinks:"
check_symlink "config/flywheel" "../../.flywheel" "config/flywheel"

echo ""
echo "State symlinks:"
check_symlink "state/beads" "../../.beads" "state/beads"

echo ""
echo "Runtime symlinks:"
check_symlink "runtime/pids" "../../pids" "runtime/pids"
check_symlink "runtime/panes" "../../panes" "runtime/panes"
check_symlink "runtime/tmp" "../../tmp" "runtime/tmp"
check_symlink "runtime/logs" "../../state/logs" "runtime/logs"
check_symlink "runtime/sessions" "../../.session-state" "runtime/sessions"

echo ""
echo "Coordination symlinks:"
check_symlink "coordination/profiles" "../../.agent-profiles" "coordination/profiles"
check_symlink "coordination/workflows" "../../.agent-workflows" "coordination/workflows"
check_symlink "coordination/active" "../../.active-agents" "coordination/active"

echo ""
echo "Tools symlinks:"
check_symlink "tools/agent-mail-helper.sh" "../../scripts/agent-mail-helper.sh" "tools/agent-mail-helper.sh"
check_symlink "tools/agent-registry.sh" "../../scripts/agent-registry.sh" "tools/agent-registry.sh"
check_symlink "tools/auto-register-agent.sh" "../../scripts/auto-register-agent.sh" "tools/auto-register-agent.sh"
check_symlink "tools/mail-monitor-ctl.sh" "../../scripts/mail-monitor-ctl.sh" "tools/mail-monitor-ctl.sh"
check_symlink "tools/monitor-agent-mail-to-terminal.sh" "../../scripts/monitor-agent-mail-to-terminal.sh" "tools/monitor-agent-mail-to-terminal.sh"

echo ""
echo "Mail symlink (optional, may not exist):"
if [ -L "$AGENTCORE_ROOT/mail/repo" ]; then
  check_symlink "mail/repo" "$HOME/.mcp_agent_mail_local_repo" "mail/repo"
else
  echo "ℹ Mail repo symlink not present (optional)"
fi

echo ""
if [ $FAILED -eq 0 ]; then
  echo "✓ PASS: All expected symlinks exist and resolve correctly"
  exit 0
else
  echo "❌ FAIL: One or more symlink checks failed"
  exit 1
fi
