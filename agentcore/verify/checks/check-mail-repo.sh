#!/usr/bin/env bash
# Verify external mail repo is reachable
# The mail repo is shared workspace-global infrastructure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTCORE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "Checking external mail repository..."

# Check if repo-location.txt exists
REPO_LOCATION_FILE="$AGENTCORE_ROOT/mail/repo-location.txt"
if [ ! -f "$REPO_LOCATION_FILE" ]; then
  echo "❌ FAIL: Mail repo location file not found: $REPO_LOCATION_FILE"
  exit 1
fi

# Read the repo location
MAIL_REPO_PATH=$(cat "$REPO_LOCATION_FILE")

# Check if the path is non-empty
if [ -z "$MAIL_REPO_PATH" ]; then
  echo "❌ FAIL: Mail repo location file is empty"
  exit 1
fi

echo "  Mail repo path: $MAIL_REPO_PATH"

# Check if the mail repo directory exists and is readable
if [ ! -d "$MAIL_REPO_PATH" ]; then
  echo "❌ FAIL: Mail repo directory does not exist: $MAIL_REPO_PATH"
  exit 1
fi

if [ ! -r "$MAIL_REPO_PATH" ]; then
  echo "❌ FAIL: Mail repo directory is not readable: $MAIL_REPO_PATH"
  exit 1
fi

# Check for expected mail repo structure
if [ ! -d "$MAIL_REPO_PATH/mail_store" ]; then
  echo "⚠ WARNING: Expected mail_store/ subdirectory not found"
  echo "  This may indicate mail repo is not initialized"
fi

echo "✓ PASS: External mail repo is reachable at $MAIL_REPO_PATH"
exit 0
