#!/usr/bin/env bash
# Setup development environment for UBS

set -euo pipefail

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Setting up UBS development environment..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Configure git hooks
echo "1. Configuring git hooks..."
git config core.hooksPath .githooks
echo "   ✓ Git will use .githooks/ directory"
echo ""

# Verify checksums
echo "2. Verifying module checksums..."
if ./scripts/verify_checksums.sh; then
  echo ""
else
  echo ""
  echo "   ⚠️  Checksums don't match - running update..."
  ./scripts/update_checksums.sh
  echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ Development environment setup complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "  - Pre-commit hook will auto-update checksums when modules change"
echo "  - Test suite will verify checksums before running tests"
echo "  - Run tests: ./test-suite/run_all.sh"
echo ""
