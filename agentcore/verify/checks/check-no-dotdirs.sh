#!/usr/bin/env bash
# Check that no hidden .directories exist inside agentcore/
# These should be at project root and referenced via symlinks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTCORE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "Checking for hidden directories inside agentcore/..."

# Find any .directories inside agentcore (excluding .git artifacts)
HIDDEN_DIRS=$(find "$AGENTCORE_ROOT" -type d -name ".*" \
  ! -name ".git" \
  ! -path "*/.git/*" \
  ! -name "." \
  ! -name ".." \
  2>/dev/null || true)

if [ -n "$HIDDEN_DIRS" ]; then
  echo "❌ FAIL: Found hidden directories inside agentcore/"
  echo "$HIDDEN_DIRS"
  echo ""
  echo "Invariant violated: No .dotdirs should exist inside agentcore/"
  echo "Hidden state should be at project root, referenced via symlinks."
  exit 1
fi

echo "✓ PASS: No hidden directories found inside agentcore/"
exit 0
