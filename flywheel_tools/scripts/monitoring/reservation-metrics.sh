#!/usr/bin/env bash
# Reservation Metrics Tool - MCP Agent Mail Integration
# Provides observability into file reservation usage across agents
# Usage: ./scripts/reservation-metrics.sh [options]

# Note: -e flag omitted for graceful error handling with jq pipelines
set -uo pipefail

# Source shared project configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_FLYWHEEL_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib/project-config.sh"

# Mail server configuration
MAIL_SERVER="${MAIL_SERVER:-http://127.0.0.1:8765}"
MCP_AGENT_MAIL_DIR="${MCP_AGENT_MAIL_DIR:-$HOME/mcp_agent_mail}"
TOKEN_FILE="$MCP_AGENT_MAIL_DIR/.env"

# Configuration
PROJECT_KEY="${PROJECT_KEY:-$MAIL_PROJECT_KEY}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Load token
if [ ! -f "$TOKEN_FILE" ]; then
    echo -e "${RED}Error: Token file not found at $TOKEN_FILE${NC}"
    echo "Is the MCP Agent Mail server running?"
    exit 1
fi
TOKEN=$(grep HTTP_BEARER_TOKEN "$TOKEN_FILE" | cut -d'=' -f2)

# Make MCP resource call
mcp_resource() {
    local uri=$1

    local payload=$(cat <<EOF
{
  "jsonrpc": "2.0",
  "method": "resources/read",
  "params": {
    "uri": "$uri"
  },
  "id": $(date +%s)
}
EOF
)

    curl -s -X POST "$MAIL_SERVER/mcp" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "$payload"
}

usage() {
    cat <<EOF
Reservation Metrics Tool - Observability for file reservations

USAGE:
    $0 [options]

OPTIONS:
    --format=table|json     Output format (default: table)
    --help, -h              Show this help

METRICS DISPLAYED:
    - Total active reservations
    - Reservations by agent
    - Average remaining TTL
    - Count by exclusive/shared mode
    - Reservations expiring soon (<15 min)

EXAMPLES:
    $0                      Show metrics in table format
    $0 --format=json        Show metrics as JSON

NOTE: Metrics are based on currently active reservations only.
      Historical conflict data is not available through the MCP API.

EOF
    exit 0
}

# Format duration in human-readable form
format_duration() {
    local seconds=$1

    # Handle empty or invalid input
    if [ -z "$seconds" ] || [ "$seconds" = "null" ]; then
        echo "N/A"
        return
    fi

    if [ $seconds -lt 0 ]; then
        echo "expired"
        return
    fi

    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))

    if [ $hours -gt 0 ]; then
        echo "${hours}h ${minutes}m"
    elif [ $minutes -gt 0 ]; then
        echo "${minutes}m ${secs}s"
    else
        echo "${secs}s"
    fi
}

# Get all active reservations
get_reservations() {
    local slug=$(echo "$PROJECT_KEY" | sed 's/^\/\+//' | tr '/' '-' | tr '[:upper:]' '[:lower:]')
    local response=$(mcp_resource "resource://file_reservations/$slug?active_only=true")

    # Check for errors
    local error=$(echo "$response" | jq -r '.error.message // empty')
    if [ -n "$error" ]; then
        echo -e "${RED}Error: $error${NC}" >&2
        exit 1
    fi

    # Return the reservations array
    echo "$response" | jq -r '.result.contents[0].text' 2>/dev/null || echo "[]"
}

# Calculate metrics
calculate_metrics() {
    local reservations=$1
    local format=${2:-table}

    if [ -z "$reservations" ] || [ "$reservations" = "null" ] || [ "$reservations" = "[]" ]; then
        if [ "$format" = "json" ]; then
            cat <<EOF
{
  "total_active": 0,
  "by_agent": {},
  "by_mode": {
    "exclusive": 0,
    "shared": 0
  },
  "avg_ttl_remaining_seconds": 0,
  "expiring_soon": []
}
EOF
        else
            echo -e "${YELLOW}No active reservations found.${NC}"
        fi
        return
    fi

    local now=$(date -u +%s)
    local total=$(echo "$reservations" | jq 'length')
    local exclusive_count=$(echo "$reservations" | jq '[.[] | select(.exclusive == true)] | length')
    local shared_count=$(echo "$reservations" | jq '[.[] | select(.exclusive == false)] | length')

    # Calculate TTL metrics and group by agent using jq
    local expiring_soon_threshold=900  # 15 minutes

    # Use jq to compute metrics (more portable than bash associative arrays)
    local metrics_json=$(echo "$reservations" | jq --arg now "$now" --arg threshold "$expiring_soon_threshold" '
    # Helper function to parse timestamp (handles microseconds)
    def parse_ts: gsub("\\.[0-9]+\\+00:00$"; "Z") | gsub("\\+00:00$"; "Z") | fromdateiso8601;

    {
      total_active: length,
      by_agent: (group_by(.agent) | map({key: .[0].agent, value: length}) | from_entries),
      by_mode: {
        exclusive: [.[] | select(.exclusive == true)] | length,
        shared: [.[] | select(.exclusive == false)] | length
      },
      ttl_data: [.[] |
        .expires_ts as $exp |
        ($exp | parse_ts) as $exp_epoch |
        ($now | tonumber) as $now_num |
        ($exp_epoch - $now_num) as $remaining |
        {
          id: .id,
          agent: .agent,
          path: .path_pattern,
          remaining: $remaining,
          expires_ts: .expires_ts
        }
      ],
      avg_ttl_remaining_seconds: (
        [.[] |
          .expires_ts as $exp |
          ($exp | parse_ts) as $exp_epoch |
          ($now | tonumber) as $now_num |
          ($exp_epoch - $now_num)
        ] |
        if length > 0 then (add / length) else 0 end | floor
      ),
      expiring_soon: [.[] |
        .expires_ts as $exp |
        ($exp | parse_ts) as $exp_epoch |
        ($now | tonumber) as $now_num |
        ($exp_epoch - $now_num) as $remaining |
        ($threshold | tonumber) as $thresh |
        select($remaining <= $thresh and $remaining > 0) |
        {
          id: .id,
          agent: .agent,
          path: .path_pattern,
          remaining_seconds: $remaining
        }
      ]
    }
    ')

    # Output based on format
    if [ "$format" = "json" ]; then
        # Remove ttl_data field (internal use only)
        echo "$metrics_json" | jq 'del(.ttl_data)'
    else
        # Table format - extract values from JSON
        local total=$(echo "$metrics_json" | jq -r '.total_active')
        local avg_ttl=$(echo "$metrics_json" | jq -r '.avg_ttl_remaining_seconds')
        local exclusive_count=$(echo "$metrics_json" | jq -r '.by_mode.exclusive')
        local shared_count=$(echo "$metrics_json" | jq -r '.by_mode.shared')

        echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}${CYAN}  File Reservation Metrics${NC}"
        echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${NC}"
        echo ""

        echo -e "${BOLD}Overview:${NC}"
        echo -e "  Total active reservations: ${GREEN}$total${NC}"
        echo -e "  Average TTL remaining:     ${BLUE}$(format_duration $avg_ttl)${NC}"
        echo ""

        echo -e "${BOLD}By Mode:${NC}"
        echo -e "  Exclusive: ${GREEN}$exclusive_count${NC}"
        echo -e "  Shared:    ${GREEN}$shared_count${NC}"
        echo ""

        echo -e "${BOLD}By Agent:${NC}"
        local agent_list=$(echo "$metrics_json" | jq -r '.by_agent | to_entries | .[] | "  \u001b[0;34m\(.key)\u001b[0m: \u001b[0;32m\(.value)\u001b[0m"' | sort)
        if [ -z "$agent_list" ]; then
            echo "  (none)"
        else
            echo "$agent_list"
        fi
        echo ""

        local expiring_count=$(echo "$metrics_json" | jq -r '.expiring_soon | length')
        if [ -n "$expiring_count" ] && [ "$expiring_count" -gt 0 ]; then
            echo -e "${BOLD}${YELLOW}⚠️  Expiring Soon (<15 min):${NC}"
            echo "$metrics_json" | jq -r '.expiring_soon[] | "  [ID \(.id)] \u001b[0;34m\(.agent)\u001b[0m: \(.path) (\(.remaining_seconds)s remaining)"' | while read -r line; do
                # Parse and format duration
                if [[ "$line" =~ \(([0-9]+)s\ remaining\) ]]; then
                    local secs="${BASH_REMATCH[1]}"
                    local formatted=$(format_duration $secs)
                    line="${line//${secs}s remaining/$formatted remaining}"
                fi
                echo -e "$line"
            done
            echo ""
        fi

        echo -e "${BOLD}Commands:${NC}"
        echo -e "  View all:    ${CYAN}./scripts/reserve-files.sh list-all${NC}"
        echo -e "  Renew yours: ${CYAN}./scripts/reserve-files.sh renew${NC}"
        echo ""
    fi
}

# Main
main() {
    local format="table"

    # Parse arguments
    for arg in "$@"; do
        case "$arg" in
            --format=*)
                format="${arg#*=}"
                if [ "$format" != "table" ] && [ "$format" != "json" ]; then
                    echo -e "${RED}Error: Invalid format '$format'. Use 'table' or 'json'.${NC}"
                    exit 1
                fi
                ;;
            --help|-h)
                usage
                ;;
            *)
                echo -e "${RED}Error: Unknown option '$arg'${NC}"
                usage
                ;;
        esac
    done

    # Get reservations and calculate metrics
    local reservations=$(get_reservations)
    calculate_metrics "$reservations" "$format"
}

main "$@"
