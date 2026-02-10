#!/usr/bin/env bash
# Pre-Edit Check - Verify file reservation status before editing
# Usage: ./scripts/pre-edit-check.sh <file-patterns...>
# Exit codes: 0=available, 1=reserved by others, 2=error

# Note: -e flag omitted to handle errors explicitly with proper exit codes
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESERVE_SCRIPT="$SCRIPT_DIR/reserve-files.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    cat <<EOF
Pre-Edit Check - Verify files are available before editing

USAGE:
    $0 <file-patterns...>

EXAMPLES:
    $0 src/app.py                  Check single file
    $0 'src/**' 'tests/**'         Check multiple patterns

EXIT CODES:
    0 - Files are available
    1 - Files are reserved by another agent
    2 - Error (missing arguments, invalid patterns)

ENVIRONMENT:
    BYPASS_RESERVATION  Set to 1 to bypass checks (always succeeds)

WORKFLOW:
    # Before editing, run pre-edit check
    ./scripts/pre-edit-check.sh 'src/module.py'

    # If available, reserve and edit
    ./scripts/reserve-files.sh reserve 'src/module.py'
    # ... make edits ...
    ./scripts/reserve-files.sh release

EOF
    exit 2
}

# Check arguments
if [[ $# -eq 0 ]]; then
    echo -e "${RED}Error: No file patterns specified${NC}" >&2
    usage
fi

# Check if bypass is enabled
if [[ "${BYPASS_RESERVATION:-0}" == "1" ]]; then
    echo -e "${YELLOW}⚠️  Pre-edit check bypassed (BYPASS_RESERVATION=1)${NC}"
    exit 0
fi

# Store file patterns
patterns=("$@")

echo "Pre-edit check: ${patterns[*]}"
echo ""

# Run availability check
if "$RESERVE_SCRIPT" check "${patterns[@]}"; then
    echo ""
    echo -e "${GREEN}✓ Pre-edit check passed - files are available${NC}"
    exit 0
else
    # Check command returns 1 when files are reserved
    # It already prints conflict details including holder names
    echo ""
    echo -e "${RED}✗ Pre-edit check failed - files are currently reserved${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Check who holds the reservation: ./scripts/reserve-files.sh list-all"
    echo "  2. Coordinate via agent mail: ./scripts/agent-mail-helper.sh send '<AgentName>' ..."
    echo "  3. Wait and retry, or work on different files"
    exit 1
fi
