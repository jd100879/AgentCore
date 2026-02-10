#!/usr/bin/env bash
# scripts/pre-task-block-hook.sh
# Block Task tool usage per CLAUDE.md
# No bypass - agents must use direct tools only

set -euo pipefail

# Read stdin (tool call data) but we don't need to parse it
cat > /dev/null

# Always block with clear error message
cat <<'EOF'
{
  "block": true,
  "message": "❌ Task tool is BLOCKED per CLAUDE.md

CLAUDE.md Rule: 'Do NOT use the Task tool to spawn subagents.'

Use direct tools instead:
  • Glob: Find files by pattern
  • Grep: Search file content
  • Read: Read files
  • Edit/Write: Modify files
  • Bash: Run commands

Work autonomously with direct tools only. No subagents."
}
EOF
