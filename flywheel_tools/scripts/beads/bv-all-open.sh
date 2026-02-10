#!/bin/bash
# bv-all-open: Pick projects with fzf, open BV in new iTerm tab for each
#
# Works when clicked from Finder or run from terminal.

set -euo pipefail

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
PROJECTS_DIR="${PROJECTS_DIR:-/Users/james/Projects}"
BR="/Users/james/.local/bin/br"

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

# If not running in an interactive terminal, relaunch in iTerm
if [ ! -t 0 ] || [ ! -t 1 ]; then
    osascript <<EOF
tell application "iTerm"
    activate
    if (count of windows) = 0 then
        set newWindow to (create window with default profile)
        tell current session of newWindow
            write text "'$SCRIPT_PATH'"
        end tell
    else
        tell current window
            set newTab to (create tab with default profile)
            tell current session of newTab
                write text "'$SCRIPT_PATH'"
            end tell
        end tell
    end if
end tell
EOF
    exit 0
fi

# Check fzf
if ! command -v fzf &>/dev/null; then
    echo "Error: fzf is required. Install with: brew install fzf"
    read -n 1
    exit 1
fi

# Build list of projects with beads
echo -e "${CYAN}Scanning projects for beads...${NC}"
project_entries=""
for beads_dir in "$PROJECTS_DIR"/*/.beads; do
    [ -d "$beads_dir" ] || continue
    project_path=$(dirname "$beads_dir")
    project_name=$(basename "$project_path")
    count=$(cd "$project_path" && "$BR" list --status open --status in_progress --json 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
    project_entries+="${count}|${project_name}|${project_path}"$'\n'
done

if [ -z "$project_entries" ]; then
    echo -e "${YELLOW}No projects with beads found.${NC}"
    read -n 1
    exit 0
fi

# Format for fzf: path|display
# fzf shows only the display part, but we get the full line back
fzf_list=""
while IFS='|' read -r count name path; do
    [ -z "$name" ] && continue
    fzf_list+="${path}|${name} (${count} open)"$'\n'
done <<< "$project_entries"

# Create preview script
PREVIEW_SCRIPT=$(mktemp)
cat > "$PREVIEW_SCRIPT" << 'PREVIEW'
#!/bin/bash
BR="/Users/james/.local/bin/br"
project_path=$(echo "$1" | cut -d'|' -f1)
project_name=$(basename "$project_path")

echo ""
echo "  Project: $project_name"
echo "  Path:    $project_path"
echo ""

if [ -d "$project_path/.beads" ]; then
    beads=$(cd "$project_path" && "$BR" list --status open --status in_progress 2>/dev/null)
    if [ -n "$beads" ]; then
        echo "  Open beads:"
        echo "  ────────────────────────────────────"
        echo "$beads" | while read -r bead_line; do
            echo "  $bead_line"
        done
    else
        echo "  No open beads."
    fi
fi
PREVIEW
chmod +x "$PREVIEW_SCRIPT"

# Show fzf picker - display only the name part (field 2)
selected=$(echo "$fzf_list" | sed '/^$/d' | fzf \
    --ansi \
    --multi \
    --delimiter='|' \
    --with-nth=2 \
    --header="
╔══════════════════════════════════════════════════════╗
║          BV Project Viewer                           ║
╠══════════════════════════════════════════════════════╣
║   Tab  Select Multiple  │  Enter  Open BV            ║
╚══════════════════════════════════════════════════════╝
" \
    --preview="bash '$PREVIEW_SCRIPT' {}" \
    --preview-window=right:50% \
    --reverse)

# Clean up
rm -f "$PREVIEW_SCRIPT" 2>/dev/null

if [ -z "$selected" ]; then
    echo "No projects selected."
    exit 0
fi

# Open BV in new iTerm tab for each selected project
while IFS= read -r line; do
    [ -z "$line" ] && continue
    project_path=$(echo "$line" | cut -d'|' -f1)
    project_name=$(basename "$project_path")

    [ ! -d "$project_path" ] && continue

    osascript <<EOF
tell application "iTerm"
    tell current window
        set newTab to (create tab with default profile)
        tell current session of newTab
            set name to "BV: $project_name"
            write text "cd '$project_path' && bv"
        end tell
    end tell
end tell
EOF
    echo -e "${GREEN}Opened BV for: ${project_name}${NC}"
done <<< "$selected"

echo ""
echo "Done. BV tabs opened."
sleep 1
