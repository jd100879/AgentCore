#!/usr/bin/env bash
#
# summarize-session.sh - Interactive tool for capturing agent session summaries
#
# Usage:
#   ./scripts/summarize-session.sh                    # Interactive mode
#   ./scripts/summarize-session.sh --dry-run          # Preview without creating file
#   ./scripts/summarize-session.sh --non-interactive  # Accept defaults
#   ./scripts/summarize-session.sh --no-commit        # Skip git commit
#   ./scripts/summarize-session.sh --agent NAME       # Specify agent name

set -euo pipefail

# Configuration
LOOKBACK_HOURS=${LOOKBACK_HOURS:-12}
OUTPUT_DIR="docs/sessions"

# Command-line flags
DRY_RUN=false
NON_INTERACTIVE=false
NO_COMMIT=false
AGENT_NAME=""

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --non-interactive)
      NON_INTERACTIVE=true
      shift
      ;;
    --no-commit)
      NO_COMMIT=true
      shift
      ;;
    --agent)
      AGENT_NAME="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --dry-run          Preview without creating file"
      echo "  --non-interactive  Accept defaults, no prompts"
      echo "  --no-commit        Skip git commit"
      echo "  --agent NAME       Specify agent name"
      echo "  -h, --help         Show this help"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Functions

detect_agent_name() {
  # Try git config first, then fall back to USER
  git config user.name 2>/dev/null || echo "$USER"
}

get_session_date() {
  date +%Y-%m-%d
}

get_recent_commits() {
  local agent="$1"
  local since="$2"

  if ! git rev-parse --git-dir &>/dev/null; then
    echo ""
    return
  fi

  git log --since="$since hours ago" \
    --author="$agent" \
    --format="%h|%ad|%s" \
    --date=format:"%Y-%m-%d %H:%M" 2>/dev/null || echo ""
}

extract_task_ids() {
  local commits="$1"
  if [[ -z "$commits" ]]; then
    echo ""
    return
  fi
  echo "$commits" | grep -oE 'bd-[a-z0-9]+' | sort -u || echo ""
}

get_beads_issue_info() {
  local issue_id="$1"

  if [[ ! -f .beads/beads.db ]]; then
    echo ""
    return
  fi

  sqlite3 .beads/beads.db \
    "SELECT title, status FROM issues WHERE id='$issue_id'" 2>/dev/null || echo ""
}

prompt() {
  local prompt_text="$1"
  local default="${2:-}"
  local response

  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    echo "$default"
    return
  fi

  if [[ -n "$default" ]]; then
    read -p "$prompt_text [$default]: " response
    echo "${response:-$default}"
  else
    read -p "$prompt_text: " response
    echo "$response"
  fi
}

collect_tasks() {
  local task_ids="$1"
  declare -a tasks

  if [[ -n "$task_ids" ]]; then
    echo "Tasks detected from commits:"
    for task_id in $task_ids; do
      echo "  - $task_id"

      if [[ "$NON_INTERACTIVE" == "true" ]]; then
        tasks+=("$task_id|||")
        continue
      fi

      local desc=$(prompt "    Description" "")
      local outcome=$(prompt "    Outcome" "Complete")
      tasks+=("$task_id|$desc|$outcome")
    done
  fi

  # Additional manual tasks
  if [[ "$NON_INTERACTIVE" != "true" ]]; then
    read -p "Add additional tasks not in commits? (y/n): " add_more
    while [[ "$add_more" == "y" ]]; do
      local task_id=$(prompt "  Task ID (e.g., bd-abc)")
      local desc=$(prompt "  Description")
      local outcome=$(prompt "  Outcome" "Complete")
      tasks+=("$task_id|$desc|$outcome")
      read -p "  Another task? (y/n): " add_more
    done
  fi

  # Output tasks array
  for task in "${tasks[@]}"; do
    echo "$task"
  done
}

collect_decisions() {
  declare -a decisions

  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    return
  fi

  read -p "Were any key decisions made? (y/n): " has_decisions
  if [[ "$has_decisions" == "y" ]]; then
    while true; do
      local topic=$(prompt "  Decision topic")
      local decision=$(prompt "  Decision")
      local rationale=$(prompt "  Rationale")
      decisions+=("$topic|$decision|$rationale")
      read -p "  Another decision? (y/n): " more
      [[ "$more" != "y" ]] && break
    done
  fi

  # Output decisions array
  for dec in "${decisions[@]}"; do
    echo "$dec"
  done
}

format_tasks_section() {
  local tasks_data="$1"
  local output=""

  if [[ -z "$tasks_data" ]]; then
    output="(No tasks completed)"
  else
    while IFS='|' read -r task_id desc outcome; do
      if [[ -n "$task_id" ]]; then
        if [[ -n "$desc" ]]; then
          output+="- ✅ $task_id: $desc"
          if [[ -n "$outcome" ]]; then
            output+=" - $outcome"
          fi
        else
          # Just task ID, no description (common in non-interactive mode)
          output+="- ✅ $task_id"
          if [[ -n "$outcome" && "$outcome" != "" ]]; then
            output+=" - $outcome"
          fi
        fi
        output+=$'\n'
      fi
    done <<< "$tasks_data"
  fi

  echo "$output"
}

format_decisions_section() {
  local decisions_data="$1"
  local output=""

  if [[ -z "$decisions_data" ]]; then
    output="(No key decisions documented)"
  else
    local count=1
    while IFS='|' read -r topic decision rationale; do
      if [[ -n "$topic" ]]; then
        output+="${count}. **${topic}**"$'\n'
        output+="   - **Decision:** $decision"$'\n'
        output+="   - **Rationale:** $rationale"$'\n'
        output+=$'\n'
        ((count++))
      fi
    done <<< "$decisions_data"
  fi

  echo "$output"
}

generate_summary() {
  # Format conditional sections
  local worked_well_section="${WORKED_WELL:-(No notes)}"
  local didnt_work_section="${DIDNT_WORK:-(No notes)}"
  local edge_cases_section="${EDGE_CASES:-(None discovered)}"

  local coord_section
  if [[ -n "$COORDINATED_WITH" ]]; then
    coord_section="Coordinated with: $COORDINATED_WITH"
  else
    coord_section="(No coordination notes)"
  fi

  local next_self_section
  if [[ -n "$NEXT_STEPS_SELF" ]]; then
    next_self_section="- [ ] $NEXT_STEPS_SELF"
  else
    next_self_section="(No next steps noted)"
  fi

  local next_team_section
  if [[ -n "$NEXT_STEPS_TEAM" ]]; then
    next_team_section="- [ ] $NEXT_STEPS_TEAM"
  else
    next_team_section="(No team follow-ups)"
  fi

  local context_section
  if [[ -n "$FUTURE_CONTEXT" ]]; then
    context_section="**If you're working on related areas, know that:**"$'\n'"- $FUTURE_CONTEXT"
  else
    context_section="(No specific context provided)"
  fi

  local beads_list="${TASK_IDS// /, }"
  [[ -z "$beads_list" ]] && beads_list="(none)"

  # Build the full output
  cat <<EOF
# Session Summary: $SESSION_DATE - $AGENT_NAME

**Agent:** $AGENT_NAME
**Date:** $SESSION_DATE
**Duration:** $DURATION
**Phase:** $PHASE
**Role:** $ROLE

## Work Completed

### Tasks
$(format_tasks_section "$TASKS_DATA")

### Deliverables
(To be filled in based on work completed)

## Key Decisions Made

$(format_decisions_section "$DECISIONS_DATA")

## Learnings and Discoveries

### What Worked Well
$worked_well_section

### What Didn't Work
$didnt_work_section

### Edge Cases Found
$edge_cases_section

## Coordination Notes

### Agent Interactions
$coord_section

### Communication Patterns
(To be filled in)

## Next Steps

### For This Agent
$next_self_section

### For Team
$next_team_section

## Context for Future Work

$context_section

## References

- Beads: $beads_list
- Mail threads: [bd-XXX]
- Commits: (from recent work)
- Decisions: (if applicable)

EOF
}

main() {
  echo "=== Session Summary Generator ==="
  echo ""

  # Step 1: Auto-detect metadata
  if [[ -z "$AGENT_NAME" ]]; then
    AGENT_NAME=$(detect_agent_name)
  fi
  SESSION_DATE=$(get_session_date)

  echo "Agent: $AGENT_NAME"
  echo "Date: $SESSION_DATE"
  echo ""

  # Step 2: Get recent commits
  echo "Detecting recent work..."
  RECENT_COMMITS=$(get_recent_commits "$AGENT_NAME" "$LOOKBACK_HOURS")

  if [[ -n "$RECENT_COMMITS" ]]; then
    echo "Recent commits found (last $LOOKBACK_HOURS hours):"
    echo "$RECENT_COMMITS" | head -5
    echo ""
  else
    echo "No recent commits found in last $LOOKBACK_HOURS hours"
    echo ""
  fi

  # Step 4: Extract task IDs
  TASK_IDS=$(extract_task_ids "$RECENT_COMMITS")

  if [[ -n "$TASK_IDS" ]]; then
    echo "Detected Beads tasks:"
    echo "$TASK_IDS"
    echo ""
  fi

  # Step 5: Interactive prompts
  echo "Please provide session details:"
  echo ""

  DURATION=$(prompt "Session duration (e.g., ~3 hours)" "~2 hours")

  # Phase selection
  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    PHASE="Phase 3"
  else
    echo ""
    echo "Select phase:"
    select PHASE in "Phase 1" "Phase 2" "Phase 3" "Other"; do
      if [[ -n "$PHASE" ]]; then
        break
      fi
    done
  fi

  # Role selection
  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    ROLE="Implementer"
  else
    echo ""
    echo "Select role:"
    select ROLE in "Coordinator" "Implementer" "Reviewer"; do
      if [[ -n "$ROLE" ]]; then
        break
      fi
    done
  fi

  # Collect tasks
  echo ""
  echo "=== Tasks Completed ==="
  TASKS_DATA=$(collect_tasks "$TASK_IDS")

  # Collect decisions
  echo ""
  echo "=== Key Decisions ==="
  DECISIONS_DATA=$(collect_decisions)

  # Collect learnings
  echo ""
  echo "=== Learnings ==="
  WORKED_WELL=$(prompt "What worked well?" "")
  DIDNT_WORK=$(prompt "What didn't work?" "")
  EDGE_CASES=$(prompt "Edge cases found?" "")

  # Collect coordination notes
  echo ""
  echo "=== Coordination ==="
  COORDINATED_WITH=$(prompt "Agents coordinated with (comma-separated)" "")

  # Collect next steps
  echo ""
  echo "=== Next Steps ==="
  NEXT_STEPS_SELF=$(prompt "Next steps for this agent?" "")
  NEXT_STEPS_TEAM=$(prompt "Next steps for team?" "")

  # Collect future context
  echo ""
  echo "=== Future Context ==="
  FUTURE_CONTEXT=$(prompt "Key insights for future work?" "")

  # Step 6: Generate summary
  SUMMARY=$(generate_summary)

  # Step 7: Create output file
  OUTPUT_FILE="$OUTPUT_DIR/${SESSION_DATE}-${AGENT_NAME}.md"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    echo "=== DRY RUN: Would create $OUTPUT_FILE ==="
    echo ""
    echo "$SUMMARY" | head -20
    echo "..."
    exit 0
  fi

  # Create output directory if needed
  mkdir -p "$OUTPUT_DIR"

  # Write summary
  echo "$SUMMARY" > "$OUTPUT_FILE"
  echo "✅ Created: $OUTPUT_FILE"

  # Step 8: Open in editor
  if [[ "$NON_INTERACTIVE" != "true" ]]; then
    ${EDITOR:-vim} "$OUTPUT_FILE"
  fi

  # Step 9: Optional git commit
  if [[ "$NO_COMMIT" != "true" ]] && [[ "$NON_INTERACTIVE" != "true" ]]; then
    read -p "Commit to git? (y/n): " should_commit
    if [[ "$should_commit" == "y" ]]; then
      git add "$OUTPUT_FILE"
      git commit -m "[session] Add session summary for ${SESSION_DATE} (${AGENT_NAME})"
      echo "✅ Committed to git"
    fi
  fi

  echo ""
  echo "Session summary complete!"
}

main "$@"
