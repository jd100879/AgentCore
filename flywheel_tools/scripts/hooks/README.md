# Hooks Directory

## ⚠️ Hooks Have Been Moved to Global Location

As of 2026-02-10, all beads hooks are now **global** and located at:

```
~/.claude/hooks/
```

**Global hooks:**
- `beads-pre-edit-check.sh` - Enforces bead requirement for edits
- `beads-pre-bash-check.sh` - Command allowlist enforcement  
- `beads-pre-task-block.sh` - Blocks Task tool usage
- `beads-post-bash-track.sh` - Auto-tracks bead creation/updates
- `beads-post-bead-close.sh` - Triggers next-bead.sh after closing
- `beads-session-start.sh` - Agent registration and auto-fix
- `beads-session-stop.sh` - Close reminder

## Why Global?

Hooks were migrated from project-specific to global to:
1. Ensure consistent enforcement across ALL projects
2. Centralize bug fixes and improvements
3. Eliminate duplicate hook files in each project
4. Simplify maintenance (fix once, works everywhere)

## Configuration

Hooks are configured in `~/.claude/settings.json` and apply to all projects automatically.

## History

- **bd-eny0.2**: Migrated hooks to global location
- **bd-1fua**: Fixed SCRIPT_DIR bug in pre-bash-check.sh
- **bd-eny0.2.1**: Fixed BEAD_TRACKING_FILE undefined variable
- **bd-eny0.2.2**: Fixed stale AGENT_RUNNER_BEAD validation
- **bd-eny0.2.3**: Removed duplicate hooks from AgentCore

## Backup

Old project hooks backed up to: `../deprecated/hooks-moved-to-global-2026-02-10/`
