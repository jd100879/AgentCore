#!/usr/bin/env bash
# agent-registry.sh - CRUD operations on agent type registry
#
# Usage:
#   ./scripts/agent-registry.sh list                     # List all agent types
#   ./scripts/agent-registry.sh show <type>              # Show details for a type
#   ./scripts/agent-registry.sh capabilities <type>      # List capabilities for a type
#   ./scripts/agent-registry.sh validate <type>          # Validate type exists
#   ./scripts/agent-registry.sh register <name> <type>   # Register agent instance
#   ./scripts/agent-registry.sh unregister <name>        # Unregister agent instance
#   ./scripts/agent-registry.sh active                   # List active agent instances
#
# Part of: Phase 1 NTM Implementation (bd-1f5)

set -euo pipefail

# Project root and registry paths
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TYPES_FILE="$PROJECT_ROOT/.agent-profiles/types.yaml"
INSTANCES_DIR="$PROJECT_ROOT/.agent-profiles/instances"

# Ensure directories exist
mkdir -p "$INSTANCES_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#######################################
# Print colored message
#######################################
print_msg() {
    local color="${!1}"
    local msg="$2"
    echo -e "${color}${msg}${NC}" >&2
}

#######################################
# Check if yq is available
#######################################
check_yq() {
    if ! command -v yq &> /dev/null; then
        print_msg RED "Error: yq is not installed"
        echo "yq is required for YAML parsing. Install with:" >&2
        echo "  macOS: brew install yq" >&2
        echo "  Linux: snap install yq" >&2
        exit 1
    fi
}

#######################################
# Print usage
#######################################
usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [arguments]

Commands:
  list                        List all available agent types
  show <type>                 Show details for an agent type
  capabilities <type>         List capabilities for an agent type
  validate <type>             Validate that an agent type exists
  register <name> <type>      Register an active agent instance
  unregister <name>           Unregister an agent instance
  active                      List all active agent instances
  types                       Alias for 'list'
  help                        Show this help message

Examples:
  $(basename "$0") list
  $(basename "$0") show backend
  $(basename "$0") capabilities frontend
  $(basename "$0") validate general
  $(basename "$0") register HazyFinch backend
  $(basename "$0") unregister HazyFinch
  $(basename "$0") active

EOF
}

#######################################
# List all agent types
#######################################
list_types() {
    check_yq

    if [ ! -f "$TYPES_FILE" ]; then
        print_msg RED "Error: Agent types file not found: $TYPES_FILE"
        exit 1
    fi

    echo "Available Agent Types:"
    echo "====================="

    yq eval '.agent_types[] | .name' "$TYPES_FILE" | while read -r type_name; do
        local desc=$(yq eval ".agent_types[] | select(.name == \"$type_name\") | .description" "$TYPES_FILE")
        local cap_count=$(yq eval ".agent_types[] | select(.name == \"$type_name\") | .capabilities | length" "$TYPES_FILE")
        echo "  $type_name - $desc ($cap_count capabilities)"
    done
}

#######################################
# Show details for an agent type
#######################################
show_type() {
    local type_name="$1"
    check_yq

    if [ ! -f "$TYPES_FILE" ]; then
        print_msg RED "Error: Agent types file not found: $TYPES_FILE"
        exit 1
    fi

    # Check if type exists
    if ! yq eval ".agent_types[] | select(.name == \"$type_name\") | .name" "$TYPES_FILE" | grep -q "^$type_name$"; then
        print_msg RED "Error: Agent type '$type_name' not found"
        exit 1
    fi

    echo "Agent Type: $type_name"
    echo "===================="

    local desc=$(yq eval ".agent_types[] | select(.name == \"$type_name\") | .description" "$TYPES_FILE")
    local capacity=$(yq eval ".agent_types[] | select(.name == \"$type_name\") | .capacity_limit" "$TYPES_FILE")

    echo "Description: $desc"
    echo "Capacity Limit: $capacity"
    echo ""
    echo "Capabilities:"
    yq eval ".agent_types[] | select(.name == \"$type_name\") | .capabilities[]" "$TYPES_FILE" | while read -r cap; do
        echo "  - $cap"
    done
}

#######################################
# List capabilities for an agent type
#######################################
list_capabilities() {
    local type_name="$1"
    check_yq

    if [ ! -f "$TYPES_FILE" ]; then
        print_msg RED "Error: Agent types file not found: $TYPES_FILE"
        exit 1
    fi

    # Check if type exists
    if ! yq eval ".agent_types[] | select(.name == \"$type_name\") | .name" "$TYPES_FILE" | grep -q "^$type_name$"; then
        print_msg RED "Error: Agent type '$type_name' not found"
        exit 1
    fi

    yq eval ".agent_types[] | select(.name == \"$type_name\") | .capabilities[]" "$TYPES_FILE"
}

#######################################
# Validate agent type exists
#######################################
validate_type() {
    local type_name="$1"
    check_yq

    if [ ! -f "$TYPES_FILE" ]; then
        print_msg RED "Error: Agent types file not found: $TYPES_FILE"
        exit 1
    fi

    if yq eval ".agent_types[] | select(.name == \"$type_name\") | .name" "$TYPES_FILE" | grep -q "^$type_name$"; then
        echo "valid"
        return 0
    else
        echo "invalid"
        return 1
    fi
}

#######################################
# Register an active agent instance
#######################################
register_agent() {
    local agent_name="$1"
    local agent_type="$2"

    # Validate type exists
    if ! validate_type "$agent_type" >/dev/null 2>&1; then
        print_msg RED "Error: Invalid agent type '$agent_type'"
        echo "Available types:" >&2
        yq eval '.agent_types[] | .name' "$TYPES_FILE" >&2
        exit 1
    fi

    # Create instance file
    local instance_file="$INSTANCES_DIR/${agent_name}.json"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > "$instance_file" <<EOF
{
  "name": "$agent_name",
  "type": "$agent_type",
  "registered_at": "$timestamp",
  "status": "active"
}
EOF

    print_msg GREEN "✓ Registered agent '$agent_name' as type '$agent_type'"
}

#######################################
# Unregister an agent instance
#######################################
unregister_agent() {
    local agent_name="$1"
    local instance_file="$INSTANCES_DIR/${agent_name}.json"

    if [ ! -f "$instance_file" ]; then
        print_msg YELLOW "Warning: Agent '$agent_name' not registered"
        exit 0
    fi

    rm -f "$instance_file"
    print_msg GREEN "✓ Unregistered agent '$agent_name'"
}

#######################################
# List active agent instances
#######################################
list_active() {
    if [ ! -d "$INSTANCES_DIR" ] || [ -z "$(ls -A "$INSTANCES_DIR" 2>/dev/null)" ]; then
        echo "No active agents registered"
        return 0
    fi

    echo "Active Agents:"
    echo "=============="

    for instance_file in "$INSTANCES_DIR"/*.json; do
        if [ -f "$instance_file" ]; then
            local name=$(jq -r '.name' "$instance_file")
            local type=$(jq -r '.type' "$instance_file")
            local registered=$(jq -r '.registered_at' "$instance_file")
            echo "  $name ($type) - registered: $registered"
        fi
    done
}

#######################################
# Main function
#######################################
main() {
    if [ $# -eq 0 ]; then
        usage
        exit 1
    fi

    local command="$1"
    shift

    case "$command" in
        list|types)
            list_types
            ;;
        show)
            if [ $# -lt 1 ]; then
                print_msg RED "Error: 'show' requires agent type argument"
                usage
                exit 1
            fi
            show_type "$1"
            ;;
        capabilities)
            if [ $# -lt 1 ]; then
                print_msg RED "Error: 'capabilities' requires agent type argument"
                usage
                exit 1
            fi
            list_capabilities "$1"
            ;;
        validate)
            if [ $# -lt 1 ]; then
                print_msg RED "Error: 'validate' requires agent type argument"
                usage
                exit 1
            fi
            validate_type "$1"
            ;;
        register)
            if [ $# -lt 2 ]; then
                print_msg RED "Error: 'register' requires agent name and type arguments"
                usage
                exit 1
            fi
            register_agent "$1" "$2"
            ;;
        unregister)
            if [ $# -lt 1 ]; then
                print_msg RED "Error: 'unregister' requires agent name argument"
                usage
                exit 1
            fi
            unregister_agent "$1"
            ;;
        active)
            list_active
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            print_msg RED "Error: Unknown command '$command'"
            usage
            exit 1
            ;;
    esac
}

main "$@"
