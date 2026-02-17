#!/usr/bin/env bash
# prepare-for-fresh-start.sh
# Clean stale flywheel runtime state from a spoke project before running AgentCore's ./start
#
# Usage:
#   ./scripts/prepare-for-fresh-start.sh [--dry-run] [--include-beads]
#
# What it cleans:
#   pids/         - stale agent PID files, mail-monitor PIDs, last-msg-id files, queue files
#   panes/        - stale agent identity files from previous sessions
#   .ntm/logs/    - old mail-monitor log files
#
# What it preserves:
#   scripts/      - flywheel_tools installed scripts (symlinks or copies)
#   .beads/       - bead state (preserved by default; use --include-beads to clean)
#   .agent-profiles/  - agent profile configs
#   AGENTS.md, CLAUDE.md - project docs

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DRY_RUN=false
INCLUDE_BEADS=false
ARCHIVE_DIR="$PROJECT_ROOT/review-for-delete/old-flywheel-state-$(date +%Y%m%d-%H%M%S)"
MOVED_COUNT=0
SKIPPED_COUNT=0

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Clean stale flywheel runtime state before running AgentCore's ./start.

Options:
    --dry-run        Show what would be cleaned without doing it
    --include-beads  Also clean .beads/ directory (default: preserved)
    -h, --help       Show this help

Moves stale files to: review-for-delete/old-flywheel-state-TIMESTAMP/
EOF
    exit 0
}

log_info()  { echo -e "${GREEN}✓${NC} $1"; }
log_warn()  { echo -e "${YELLOW}⚠${NC} $1"; }
log_dry()   { echo -e "${BLUE}[dry-run]${NC} Would move: $1"; }
log_skip()  { echo -e "  (skipped - empty) $1"; }

# Parse args
for arg in "$@"; do
    case "$arg" in
        --dry-run)        DRY_RUN=true ;;
        --include-beads)  INCLUDE_BEADS=true ;;
        -h|--help)        usage ;;
        *) echo "Unknown option: $arg"; usage ;;
    esac
done

echo ""
echo "=== Prepare for Fresh Start ==="
echo "Project: $PROJECT_ROOT"
if $DRY_RUN; then
    echo -e "${BLUE}Mode: DRY RUN (no files will be moved)${NC}"
fi
echo ""

# Helper: move file/dir to archive, creating archive dir as needed
archive_item() {
    local src="$1"
    local rel="${src#$PROJECT_ROOT/}"

    if $DRY_RUN; then
        log_dry "$rel"
        ((MOVED_COUNT++)) || true
        return
    fi

    mkdir -p "$ARCHIVE_DIR/$(dirname "$rel")"
    mv "$src" "$ARCHIVE_DIR/$rel"
    log_info "Archived: $rel"
    ((MOVED_COUNT++)) || true
}

# ── pids/ ──────────────────────────────────────────────────────────────────────
PIDS_DIR="$PROJECT_ROOT/pids"
if [ -d "$PIDS_DIR" ]; then
    echo "Cleaning pids/..."
    found_any=false
    while IFS= read -r -d '' f; do
        archive_item "$f"
        found_any=true
    done < <(find "$PIDS_DIR" -maxdepth 1 -type f -print0)
    if ! $found_any; then
        log_skip "pids/ (already empty)"
        ((SKIPPED_COUNT++)) || true
    fi
else
    log_warn "pids/ directory not found (skipping)"
fi

# ── panes/ ─────────────────────────────────────────────────────────────────────
PANES_DIR="$PROJECT_ROOT/panes"
if [ -d "$PANES_DIR" ]; then
    echo "Cleaning panes/..."
    found_any=false
    while IFS= read -r -d '' f; do
        archive_item "$f"
        found_any=true
    done < <(find "$PANES_DIR" -maxdepth 1 -type f -name "*.identity" -print0)
    if ! $found_any; then
        log_skip "panes/ (no .identity files)"
        ((SKIPPED_COUNT++)) || true
    fi
else
    log_warn "panes/ directory not found (skipping)"
fi

# ── .ntm/logs/ ────────────────────────────────────────────────────────────────
LOGS_DIR="$PROJECT_ROOT/.ntm/logs"
if [ -d "$LOGS_DIR" ]; then
    echo "Cleaning .ntm/logs/..."
    found_any=false
    while IFS= read -r -d '' f; do
        archive_item "$f"
        found_any=true
    done < <(find "$LOGS_DIR" -maxdepth 1 -type f -name "*.log" -print0)
    if ! $found_any; then
        log_skip ".ntm/logs/ (no log files)"
        ((SKIPPED_COUNT++)) || true
    fi
else
    log_warn ".ntm/logs/ directory not found (skipping)"
fi

# ── .beads/ (optional) ────────────────────────────────────────────────────────
if $INCLUDE_BEADS; then
    BEADS_DIR="$PROJECT_ROOT/.beads"
    if [ -d "$BEADS_DIR" ]; then
        echo "Cleaning .beads/..."
        found_any=false
        while IFS= read -r -d '' f; do
            archive_item "$f"
            found_any=true
        done < <(find "$BEADS_DIR" -type f -print0)
        if ! $found_any; then
            log_skip ".beads/ (already empty)"
            ((SKIPPED_COUNT++)) || true
        fi
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=== Summary ==="
if [ "$MOVED_COUNT" -gt 0 ]; then
    if $DRY_RUN; then
        echo -e "${BLUE}Would archive $MOVED_COUNT item(s).${NC}"
    else
        echo -e "${GREEN}Archived $MOVED_COUNT item(s) to:${NC}"
        echo "  $ARCHIVE_DIR"
    fi
fi
if [ "$SKIPPED_COUNT" -gt 0 ]; then
    echo "Skipped $SKIPPED_COUNT already-empty location(s)."
fi
if [ "$MOVED_COUNT" -eq 0 ] && [ "$SKIPPED_COUNT" -gt 0 ]; then
    echo -e "${GREEN}Project is already clean — nothing to archive.${NC}"
fi
echo ""
if ! $DRY_RUN && [ "$MOVED_COUNT" -gt 0 ]; then
    echo "You can safely delete the archive once AgentCore's ./start succeeds:"
    echo "  rm -rf \"$ARCHIVE_DIR\""
fi
