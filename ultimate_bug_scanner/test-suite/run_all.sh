#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

# CRITICAL: Verify checksums BEFORE running tests
# This prevents deploying broken code where modules don't match checksums
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 1: Verifying module checksums..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if ! ../scripts/verify_checksums.sh; then
  echo ""
  echo "❌ CHECKSUM VERIFICATION FAILED"
  echo "Tests will NOT run until checksums are fixed."
  exit 1
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 2: Running test suite..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if command -v uv >/dev/null 2>&1; then
  uv run python ./run_manifest.py "$@"
  uv run python shareable/test_shareable_reports.py
  uv run python python/tests/test_resource_helper.py
  uv run python java/tests/test_resource_lifecycle_helper.py
else
  echo "[warn] uv not found – falling back to system python3. Run 'uv sync --python 3.13' for the supported toolchain." >&2
  python3 ./run_manifest.py "$@"
  python3 shareable/test_shareable_reports.py
  python3 python/tests/test_resource_helper.py
  python3 java/tests/test_resource_lifecycle_helper.py
fi
