#!/usr/bin/env bash
# Reservation Status Dashboard
# Pretty-prints all active file reservations across all agents
# Usage: ./scripts/reservation-status.sh

# Note: -e flag omitted for graceful error handling with jq pipelines
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESERVE_SCRIPT="$SCRIPT_DIR/reserve-files.sh"

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

usage() {
    cat <<EOF
Reservation Status Dashboard - View all active file reservations

USAGE:
    $0

Displays a formatted table of all active reservations sorted by agent and expiration.

COLUMNS:
    AGENT       - Agent name holding the reservation
    ID          - Reservation identifier
    PATH        - File pattern reserved
    EXCLUSIVE   - Whether lock is exclusive (Y/N)
    EXPIRES     - Expiration timestamp

EOF
    exit 0
}

# Check for help flag
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    usage
fi

# Get raw reservation data from list-all
RAW_DATA=$("$RESERVE_SCRIPT" list-all 2>/dev/null | tail -n +3)

# Check if there are any reservations
if [ -z "$RAW_DATA" ] || echo "$RAW_DATA" | grep -q "^(No active reservations)"; then
    echo -e "${CYAN}Reservation Status Dashboard${NC}"
    echo "============================"
    echo ""
    echo "(No active reservations)"
    exit 0
fi

# Print header
echo -e "${CYAN}${BOLD}Reservation Status Dashboard${NC}"
echo "============================"
echo ""

# Parse and format the data
# Input format: [AgentName] path_pattern (ID: 123, exclusive: true, expires: timestamp)
# Parse using sed for BSD/GNU compatibility

# Print table header
printf "%-20s %-6s %-40s %-9s %s\n" "AGENT" "ID" "PATH" "EXCLUSIVE" "EXPIRES"
printf "%-20s %-6s %-40s %-9s %s\n" "--------------------" "------" "----------------------------------------" "---------" "----------------------------"

# Process each line and store for sorting
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

echo "$RAW_DATA" | while IFS= read -r line; do
    # Extract agent name (between brackets)
    agent=$(echo "$line" | sed -n 's/^[[:space:]]*\[\([^]]*\)\].*/\1/p')

    # Extract path (between ] and (ID:)
    path=$(echo "$line" | sed -n 's/^[^]]*\][[:space:]]*\([^(]*\)[[:space:]]*(.*/\1/p')

    # Extract ID
    id=$(echo "$line" | sed -n 's/.*ID:[[:space:]]*\([0-9]*\).*/\1/p')

    # Extract exclusive flag
    excl=$(echo "$line" | sed -n 's/.*exclusive:[[:space:]]*\([^,]*\).*/\1/p')
    if [ "$excl" = "true" ]; then
        exclusive="Y"
    else
        exclusive="N"
    fi

    # Extract expires timestamp
    expires=$(echo "$line" | sed -n 's/.*expires:[[:space:]]*\([^)]*\).*/\1/p')

    # Truncate path if too long
    if [ ${#path} -gt 40 ]; then
        path="${path:0:37}..."
    fi

    # Output formatted line with sort key prefix
    printf "%s:%s\t%-20s %-6s %-40s %-9s %s\n" "$agent" "$expires" "$agent" "$id" "$path" "$exclusive" "$expires"
done | sort -t: -k1,1 -k2,2 > "$TEMP_FILE"

# Print sorted output without sort keys
cut -f2- "$TEMP_FILE"

echo ""
echo -e "${GREEN}Tip:${NC} Use './scripts/reserve-files.sh list' to see only your reservations"
echo -e "${GREEN}Tip:${NC} Use './scripts/reserve-files.sh release --id <ID>' to release a specific reservation"
