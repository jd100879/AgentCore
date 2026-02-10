#!/bin/bash
# bv-all.sh - View beads from all projects
#
# Shows open beads across all projects with project names

set -uo pipefail

PROJECTS_DIR="${PROJECTS_DIR:-/Users/james/Projects}"
BR="${BR:-/Users/james/.local/bin/br}"

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

show_help() {
    echo "Usage: bv-all.sh [options]"
    echo ""
    echo "View beads from all projects in one view."
    echo ""
    echo "Options:"
    echo "  --open       Show only open beads (default)"
    echo "  --all        Show all beads including closed"
    echo "  --in-progress Show only in-progress beads"
    echo "  --help       Show this help"
    echo ""
    echo "Output format:"
    echo "  BEAD_ID  PROJECT_NAME  STATUS  TITLE"
}

# Default filter
FILTER="open"

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --open) FILTER="open"; shift ;;
        --all) FILTER="all"; shift ;;
        --in-progress) FILTER="in_progress"; shift ;;
        --help) show_help; exit 0 ;;
        *) echo "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

# Find all projects with .beads directory
found=0

for beads_dir in "$PROJECTS_DIR"/*/.beads; do
    [ -d "$beads_dir" ] || continue

    project_path=$(dirname "$beads_dir")
    project_name=$(basename "$project_path")

    # Get beads from this project
    if [ "$FILTER" = "all" ]; then
        beads=$(cd "$project_path" && "$BR" list --json 2>/dev/null | jq -r '.[] | "\(.id)\t\(.status)\t\(.title)"' 2>/dev/null)
    elif [ "$FILTER" = "in_progress" ]; then
        beads=$(cd "$project_path" && "$BR" list --status in_progress --json 2>/dev/null | jq -r '.[] | "\(.id)\t\(.status)\t\(.title)"' 2>/dev/null)
    else
        beads=$(cd "$project_path" && "$BR" list --status open --status in_progress --json 2>/dev/null | jq -r '.[] | "\(.id)\t\(.status)\t\(.title)"' 2>/dev/null)
    fi

    # Print beads with project name
    if [ -n "$beads" ]; then
        while IFS=$'\t' read -r id status title; do
            [ -z "$id" ] && continue
            printf "${GREEN}%-10s${NC} ${CYAN}%-30s${NC} ${YELLOW}%-12s${NC} %s\n" "$id" "$project_name" "$status" "$title"
            ((found++))
        done <<< "$beads"
    fi
done

if [ "$found" -eq 0 ]; then
    echo "No beads found across projects."
else
    echo ""
    echo "Found $found bead(s) across projects."
fi
