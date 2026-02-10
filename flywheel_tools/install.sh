#!/usr/bin/env bash
set -euo pipefail

# Flywheel Tools Installation Script
# Installs flywheel_tools into a target project directory

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
FLYWHEEL_ROOT="$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    cat << EOF
Usage: $0 [OPTIONS] <target_project_dir>

Install flywheel_tools into a target project directory.

Options:
    -h, --help              Show this help message
    -s, --symlink           Use symlinks instead of copying scripts (default)
    -c, --copy              Copy scripts instead of symlinking
    -f, --force             Overwrite existing files
    --skip-deps             Skip dependency validation
    --skip-claude-md        Skip CLAUDE.md updates

Arguments:
    target_project_dir      Target project directory to install into

Example:
    $0 ~/Projects/my-agent-project
    $0 --copy ~/Projects/my-agent-project

EOF
    exit 1
}

log_info() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

validate_dependencies() {
    log_info "Validating dependencies..."
    local missing_deps=()
    
    for dep in tmux jq curl git; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_error "Please install them and try again"
        exit 1
    fi
    
    log_info "All dependencies satisfied"
}

create_directories() {
    local target="$1"
    
    log_info "Creating project directories..."
    
    mkdir -p "$target/scripts"
    mkdir -p "$target/.beads"
    mkdir -p "$target/.agent-profiles"
    mkdir -p "$target/.session-state"
    
    log_info "Directories created"
}

install_scripts() {
    local target="$1"
    local method="$2"  # "symlink" or "copy"
    
    log_info "Installing scripts using $method..."
    
    local categories=("core" "hooks" "beads" "terminal" "fleet" "monitoring" "dev" "adapters" "lib")
    
    for category in "${categories[@]}"; do
        local src_dir="$FLYWHEEL_ROOT/scripts/$category"
        local target_dir="$target/scripts"
        
        if [ ! -d "$src_dir" ]; then
            continue
        fi
        
        # Find all .sh files in the category
        while IFS= read -r -d '' script; do
            local script_name=$(basename "$script")
            local target_path="$target_dir/$script_name"
            
            if [ -f "$target_path" ] && [ "$FORCE" != "true" ]; then
                log_warn "Skipping $script_name (already exists, use --force to overwrite)"
                continue
            fi
            
            if [ "$method" = "symlink" ]; then
                ln -sf "$script" "$target_path"
            else
                cp "$script" "$target_path"
                chmod +x "$target_path"
            fi
            
            log_info "Installed $script_name"
        done < <(find "$src_dir" -name "*.sh" -type f -print0)
    done
}

update_claude_md() {
    local target="$1"
    local claude_md="$target/CLAUDE.md"
    
    if [ "$SKIP_CLAUDE_MD" = "true" ]; then
        return
    fi
    
    log_info "Updating CLAUDE.md..."
    
    if [ ! -f "$claude_md" ]; then
        log_warn "CLAUDE.md not found, creating new one"
        cat > "$claude_md" << 'EOF'
# Project Instructions

## Flywheel Tools Integration

This project uses AgentCore flywheel_tools for agent workflow automation.

### Beads Workflow (MANDATORY)

All work MUST be tracked with a bead. Hooks block edits without one.

- Start work: `./scripts/br-start-work.sh "Title"` or `./scripts/bv-claim.sh`
- Create sub-beads: `./scripts/br-create.sh "Title" --parent bd-xxx`
- Commits: `git commit -m "[bd-xxx] message"`
- Close: `br close bd-xxx`

### Agent Mail

Check identity and inbox:
- `./scripts/agent-mail-helper.sh whoami`
- `./scripts/agent-mail-helper.sh inbox`

### Development

- Health check: `./scripts/doctor.sh`
- Hook bypass (testing only): `./scripts/hook-bypass.sh on|off|status`

EOF
        log_info "Created CLAUDE.md with flywheel_tools instructions"
    else
        if ! grep -q "flywheel_tools" "$claude_md"; then
            log_warn "CLAUDE.md exists but doesn't mention flywheel_tools"
            log_warn "Please manually add flywheel_tools instructions"
        else
            log_info "CLAUDE.md already references flywheel_tools"
        fi
    fi
}

# Parse arguments
FORCE="false"
SKIP_DEPS="false"
SKIP_CLAUDE_MD="false"
INSTALL_METHOD="symlink"
TARGET_DIR=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -s|--symlink)
            INSTALL_METHOD="symlink"
            shift
            ;;
        -c|--copy)
            INSTALL_METHOD="copy"
            shift
            ;;
        -f|--force)
            FORCE="true"
            shift
            ;;
        --skip-deps)
            SKIP_DEPS="true"
            shift
            ;;
        --skip-claude-md)
            SKIP_CLAUDE_MD="true"
            shift
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            ;;
        *)
            TARGET_DIR="$1"
            shift
            ;;
    esac
done

# Validate target directory
if [ -z "$TARGET_DIR" ]; then
    log_error "Target project directory required"
    usage
fi

if [ ! -d "$TARGET_DIR" ]; then
    log_error "Target directory does not exist: $TARGET_DIR"
    exit 1
fi

# Convert to absolute path
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

log_info "Installing flywheel_tools to: $TARGET_DIR"
log_info "Method: $INSTALL_METHOD"

# Run installation steps
if [ "$SKIP_DEPS" != "true" ]; then
    validate_dependencies
fi

create_directories "$TARGET_DIR"
install_scripts "$TARGET_DIR" "$INSTALL_METHOD"
update_claude_md "$TARGET_DIR"

log_info ""
log_info "Installation complete!"
log_info ""
log_info "Next steps:"
log_info "1. Review and customize $TARGET_DIR/CLAUDE.md"
log_info "2. Configure agent profiles in $TARGET_DIR/.agent-profiles/"
log_info "3. Start your first agent with: cd $TARGET_DIR && ./scripts/agent-runner.sh"
log_info ""

