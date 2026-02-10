#!/bin/bash
# sync-beads-to-project.sh - Copy beads workflow scripts to a target project
# Called automatically when creating/attaching sessions via ./start

set -euo pipefail

TARGET_PROJECT="${1:-}"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$TARGET_PROJECT" ]; then
    echo "Usage: sync-beads-to-project.sh <target_project_path>"
    exit 1
fi

if [ ! -d "$TARGET_PROJECT" ]; then
    echo "Error: Target project not found: $TARGET_PROJECT"
    exit 1
fi

# Skip if target is the source (agent-flywheel-integration itself)
if [ "$(cd "$TARGET_PROJECT" && pwd)" = "$(cd "$SOURCE_DIR/.." && pwd)" ]; then
    exit 0
fi

echo "Syncing beads workflow to: $TARGET_PROJECT"

# Create scripts directory if needed
mkdir -p "$TARGET_PROJECT/scripts"

# Core lifecycle scripts (agent-runner loop, bead transitions, enforcement hooks)
SCRIPTS=(
    # Core lifecycle
    "agent-runner.sh"
    "next-bead.sh"
    "post-bead-close-hook.sh"
    "post-bash-bead-track-hook.sh"
    "pre-bash-bead-check-hook.sh"
    "pre-edit-check-hook.sh"
    "pre-edit-check.sh"
    "br-create.sh"
    "br-wrapper.sh"
    # Required dependencies
    "agent-mail-helper.sh"
    "monitor-agent-mail-to-terminal.sh"
    "mail-monitor-ctl.sh"
    "terminal-inject.sh"
    "broadcast-to-swarm.sh"
    "br-start-work.sh"
    "bv-claim.sh"
    "log-bead-activity.sh"
    "session-start-hook.sh"
    "session-stop-hook.sh"
    "auto-register-agent.sh"
    "lib-infer-type.sh"
    # Pane management
    "cleanup-after-pane-removal.sh"
    "renumber-panes.sh"
    # Monitors
    "bead-stale-monitor.sh"
    # Utilities
    "hook-bypass.sh"
    "reserve-files.sh"
    # Pane utilities
    "arrange-panes.sh"
    # LLM wrappers
    "grok-claude-wrapper.sh"
    "deepseek-claude-wrapper.sh"
    "start-deepseek-proxy.sh"
    # Hook enforcement
    "pre-task-block-hook.sh"
    # Session management
    "visual-session-manager.sh"
    # Autonomous workflows
    "wake-agents.sh"
    "self-review.sh"
)

# Copy scripts (update if different)
# Skip files that are symlinks to AgentCore (installed via flywheel_tools/install.sh)
copied=0
skipped_symlinks=0
for script in "${SCRIPTS[@]}"; do
    if [ -f "$SOURCE_DIR/$script" ]; then
        dst="$TARGET_PROJECT/scripts/$script"

        # Check if destination is a symlink to AgentCore
        if [ -L "$dst" ]; then
            link_target=$(readlink "$dst" 2>/dev/null || echo "")
            if [[ "$link_target" == *"/AgentCore/"* ]]; then
                # Skip - already symlinked to AgentCore (installed via install.sh)
                skipped_symlinks=$((skipped_symlinks + 1))
                continue
            fi
        fi

        # Copy if file does not exist or differs
        if [ ! -f "$dst" ] || ! diff -q "$SOURCE_DIR/$script" "$dst" >/dev/null 2>&1; then
            cp "$SOURCE_DIR/$script" "$dst"
            chmod +x "$dst"
            copied=$((copied + 1))
        fi
    fi
done

if [ "$copied" -gt 0 ]; then
    echo "  Updated $copied scripts in $TARGET_PROJECT/scripts/"
fi

if [ "$skipped_symlinks" -gt 0 ]; then
    echo "  Skipped $skipped_symlinks scripts (already symlinked to AgentCore)"
fi

# Copy lib/ directory (shared libraries, update if different)
if [ -d "$SOURCE_DIR/lib" ]; then
    mkdir -p "$TARGET_PROJECT/scripts/lib"
    lib_copied=0
    lib_skipped_symlinks=0
    for libfile in "$SOURCE_DIR/lib/"*; do
        [ -f "$libfile" ] || continue
        fname=$(basename "$libfile")
        dst="$TARGET_PROJECT/scripts/lib/$fname"
        # Check if destination is a symlink to AgentCore
        if [ -L "$dst" ]; then
            link_target=$(readlink "$dst" 2>/dev/null || echo "")
            if [[ "$link_target" == *"/AgentCore/"* ]]; then
                lib_skipped_symlinks=$((lib_skipped_symlinks + 1))
                continue
            fi
        fi
        if [ ! -f "$dst" ] || ! diff -q "$libfile" "$dst" >/dev/null 2>&1; then
            cp "$libfile" "$dst"
            lib_copied=$((lib_copied + 1))
        fi
    done
    if [ "$lib_copied" -gt 0 ]; then
        echo "  Updated $lib_copied files in scripts/lib/"
    fi
fi

# Copy panes/ directory (discover.sh and runtime identity files pattern)
PANES_SRC="$SOURCE_DIR/../panes"
if [ -d "$PANES_SRC" ]; then
    mkdir -p "$TARGET_PROJECT/panes"
    panes_copied=0
    panes_skipped_symlinks=0
    for panefile in "$PANES_SRC"/*.sh; do
        [ -f "$panefile" ] || continue
        fname=$(basename "$panefile")
        dst="$TARGET_PROJECT/panes/$fname"
        # Check if destination is a symlink to AgentCore
        if [ -L "$dst" ]; then
            link_target=$(readlink "$dst" 2>/dev/null || echo "")
            if [[ "$link_target" == *"/AgentCore/"* ]]; then
                panes_skipped_symlinks=$((panes_skipped_symlinks + 1))
                continue
            fi
        fi
        if [ ! -f "$dst" ] || ! diff -q "$panefile" "$dst" >/dev/null 2>&1; then
            cp "$panefile" "$dst"
            chmod +x "$dst"
            panes_copied=$((panes_copied + 1))
        fi
    done
    if [ "$panes_copied" -gt 0 ]; then
        echo "  Updated $panes_copied files in panes/"
    fi
fi

# Initialize .beads directory if not exists
if [ ! -d "$TARGET_PROJECT/.beads" ]; then
    mkdir -p "$TARGET_PROJECT/.beads"
    echo "  Created .beads directory"
fi

# Create/update .gitignore for beads artifacts
GITIGNORE="$TARGET_PROJECT/.gitignore"
BEADS_IGNORES=(
    ".beads/mail-read.jsonl"
    ".beads/mail-read-temp.jsonl"
    ".beads/*.backup"
    ".beads/agent-activity.jsonl"
    ".beads/reserve-pending/"
    ".agent-mail-project-id"
    "pids/"
)

for ignore in "${BEADS_IGNORES[@]}"; do
    if [ -f "$GITIGNORE" ]; then
        if ! grep -qF "$ignore" "$GITIGNORE" 2>/dev/null; then
            echo "$ignore" >> "$GITIGNORE"
        fi
    else
        echo "$ignore" >> "$GITIGNORE"
    fi
done

echo "  Updated .gitignore"

# Add beads workflow instructions to CLAUDE.md if not present
CLAUDE_MD="$TARGET_PROJECT/CLAUDE.md"
BEADS_MARKER="## Beads Workflow"

if [ -f "$CLAUDE_MD" ]; then
    # File exists - check if beads instructions already present
    if ! grep -q "$BEADS_MARKER" "$CLAUDE_MD" 2>/dev/null; then
        # Append beads instructions
        cat >> "$CLAUDE_MD" << 'CLAUDEMD'

## Agent Mail

**First time:** Register in the mail system:
```bash
./scripts/agent-mail-helper.sh register "Your role"
```

**Every session:** Check identity and inbox:
```bash
./scripts/agent-mail-helper.sh whoami
./scripts/agent-mail-helper.sh inbox
```

## Beads Workflow (MANDATORY)

All work MUST be tracked with a bead. Edits are blocked until you have an active bead.

**IMPORTANT: Never bypass or disable hooks. If an edit is blocked, create a bead first.**

**Start of session:**
```bash
./scripts/br-start-work.sh "Your task title"  # Create new bead
# OR
./scripts/bv-claim.sh                          # Claim recommended bead
```

**Commits:** Always prefix with bead ID:
```bash
git commit -m "[bd-xxx] Your commit message"
```

**End of work:** Close your bead:
```bash
br close bd-xxx
```
CLAUDEMD
        echo "  Appended beads instructions to CLAUDE.md"
    fi
else
    # No CLAUDE.md - create with template
    cat > "$CLAUDE_MD" << 'CLAUDEMD'
# Project Instructions

## Agent Mail

**First time:** Register in the mail system:
```bash
./scripts/agent-mail-helper.sh register "Your role"
```

**Every session:** Check identity and inbox:
```bash
./scripts/agent-mail-helper.sh whoami
./scripts/agent-mail-helper.sh inbox
```

## Beads Workflow (MANDATORY)

All work MUST be tracked with a bead. Edits are blocked until you have an active bead.

**IMPORTANT: Never bypass or disable hooks. If an edit is blocked, create a bead first.**

**Start of session:**
```bash
./scripts/br-start-work.sh "Your task title"  # Create new bead
# OR
./scripts/bv-claim.sh                          # Claim recommended bead
```

**Commits:** Always prefix with bead ID:
```bash
git commit -m "[bd-xxx] Your commit message"
```

**End of work:** Close your bead:
```bash
br close bd-xxx
```
CLAUDEMD
    echo "  Created CLAUDE.md template"
fi

# Sync AGENTS.md (update if different)
AGENTS_MD_SRC="$SOURCE_DIR/../AGENTS.md"
AGENTS_MD_DST="$TARGET_PROJECT/AGENTS.md"
if [ -f "$AGENTS_MD_SRC" ]; then
    if [ ! -f "$AGENTS_MD_DST" ] || ! diff -q "$AGENTS_MD_SRC" "$AGENTS_MD_DST" >/dev/null 2>&1; then
        cp "$AGENTS_MD_SRC" "$AGENTS_MD_DST"
        echo "  Synced AGENTS.md"
    fi
fi

# Sync tmux config (update if different)
TMUX_CONF_SRC="$SOURCE_DIR/../.tmux.conf.agent-flywheel"
TMUX_CONF_DST="$TARGET_PROJECT/.tmux.conf.agent-flywheel"
if [ -f "$TMUX_CONF_SRC" ]; then
    if [ ! -f "$TMUX_CONF_DST" ] || ! diff -q "$TMUX_CONF_SRC" "$TMUX_CONF_DST" >/dev/null 2>&1; then
        cp "$TMUX_CONF_SRC" "$TMUX_CONF_DST"
        echo "  Synced .tmux.conf.agent-flywheel"
    fi
fi

# Sync .claude/commands directory (custom slash commands)
COMMANDS_SRC="$SOURCE_DIR/../.claude/commands"
if [ -d "$COMMANDS_SRC" ]; then
    mkdir -p "$TARGET_PROJECT/.claude/commands"
    commands_copied=0
    for cmdfile in "$COMMANDS_SRC"/*.md; do
        [ -f "$cmdfile" ] || continue
        fname=$(basename "$cmdfile")
        dst="$TARGET_PROJECT/.claude/commands/$fname"
        if [ ! -f "$dst" ] || ! diff -q "$cmdfile" "$dst" >/dev/null 2>&1; then
            cp "$cmdfile" "$dst"
            commands_copied=$((commands_copied + 1))
        fi
    done
    if [ "$commands_copied" -gt 0 ]; then
        echo "  Updated $commands_copied custom commands in .claude/commands/"
    fi
fi

# Sync .claude/skills directory (custom skills)
SKILLS_SRC="$SOURCE_DIR/../.claude/skills"
if [ -d "$SKILLS_SRC" ]; then
    mkdir -p "$TARGET_PROJECT/.claude/skills"
    skills_copied=0
    for skilldir in "$SKILLS_SRC"/*; do
        [ -d "$skilldir" ] || continue
        skill_name=$(basename "$skilldir")
        mkdir -p "$TARGET_PROJECT/.claude/skills/$skill_name"
        # Copy all files in the skill directory
        for skillfile in "$skilldir"/*; do
            [ -f "$skillfile" ] || continue
            fname=$(basename "$skillfile")
            dst="$TARGET_PROJECT/.claude/skills/$skill_name/$fname"
            if [ ! -f "$dst" ] || ! diff -q "$skillfile" "$dst" >/dev/null 2>&1; then
                cp "$skillfile" "$dst"
                skills_copied=$((skills_copied + 1))
            fi
        done
    done
    if [ "$skills_copied" -gt 0 ]; then
        echo "  Updated $skills_copied custom skills in .claude/skills/"
    fi
fi

# Sync .claude/settings.local.json (conditional merge for permissions)
SETTINGS_LOCAL_SRC="$SOURCE_DIR/../.claude/settings.local.json"
SETTINGS_LOCAL_DST="$TARGET_PROJECT/.claude/settings.local.json"
if [ -f "$SETTINGS_LOCAL_SRC" ]; then
    mkdir -p "$TARGET_PROJECT/.claude"
    if [ ! -f "$SETTINGS_LOCAL_DST" ]; then
        # No existing settings.local.json - copy directly
        cp "$SETTINGS_LOCAL_SRC" "$SETTINGS_LOCAL_DST"
        echo "  Created .claude/settings.local.json with workflow permissions"
    elif ! diff -q "$SETTINGS_LOCAL_SRC" "$SETTINGS_LOCAL_DST" >/dev/null 2>&1; then
        # File exists and differs - merge permissions if possible
        if command -v jq >/dev/null 2>&1; then
            # Use jq to merge allow arrays
            jq -s '.[0] * .[1] | .permissions.allow |= (.[0] + .[1] | unique)' \
                "$SETTINGS_LOCAL_DST" "$SETTINGS_LOCAL_SRC" > "$SETTINGS_LOCAL_DST.tmp" 2>/dev/null && \
                mv "$SETTINGS_LOCAL_DST.tmp" "$SETTINGS_LOCAL_DST" && \
                echo "  Merged permissions into .claude/settings.local.json"
        fi
    fi
fi

# Sync AGENT_MAIL.md (root documentation)
AGENT_MAIL_SRC="$SOURCE_DIR/../AGENT_MAIL.md"
AGENT_MAIL_DST="$TARGET_PROJECT/AGENT_MAIL.md"
if [ -f "$AGENT_MAIL_SRC" ]; then
    if [ ! -f "$AGENT_MAIL_DST" ] || ! diff -q "$AGENT_MAIL_SRC" "$AGENT_MAIL_DST" >/dev/null 2>&1; then
        cp "$AGENT_MAIL_SRC" "$AGENT_MAIL_DST"
        echo "  Synced AGENT_MAIL.md"
    fi
fi

# Sync docs/ directory (all workflow guides)
DOCS_SRC="$SOURCE_DIR/../docs"
if [ -d "$DOCS_SRC" ]; then
    mkdir -p "$TARGET_PROJECT/docs"
    docs_copied=0
    for docfile in "$DOCS_SRC"/*.md; do
        [ -f "$docfile" ] || continue
        fname=$(basename "$docfile")
        dst="$TARGET_PROJECT/docs/$fname"
        if [ ! -f "$dst" ] || ! diff -q "$docfile" "$dst" >/dev/null 2>&1; then
            cp "$docfile" "$dst"
            docs_copied=$((docs_copied + 1))
        fi
    done
    if [ "$docs_copied" -gt 0 ]; then
        echo "  Updated $docs_copied documentation files in docs/"
    fi
fi

# Sync scripts/mail-macros/ directory
MAIL_MACROS_SRC="$SOURCE_DIR/mail-macros"
if [ -d "$MAIL_MACROS_SRC" ]; then
    mkdir -p "$TARGET_PROJECT/scripts/mail-macros"
    macros_copied=0
    for macrofile in "$MAIL_MACROS_SRC"/*; do
        [ -f "$macrofile" ] || continue
        fname=$(basename "$macrofile")
        dst="$TARGET_PROJECT/scripts/mail-macros/$fname"
        if [ ! -f "$dst" ] || ! diff -q "$macrofile" "$dst" >/dev/null 2>&1; then
            cp "$macrofile" "$dst"
            # Make executable if it's a script (not README.md)
            [ "$fname" != "README.md" ] && chmod +x "$dst"
            macros_copied=$((macros_copied + 1))
        fi
    done
    if [ "$macros_copied" -gt 0 ]; then
        echo "  Updated $macros_copied mail macros in scripts/mail-macros/"
    fi
fi

# Sync start script (main launcher)
START_SRC="$SOURCE_DIR/../start"
START_DST="$TARGET_PROJECT/start"
if [ -f "$START_SRC" ]; then
    if [ ! -f "$START_DST" ] || ! diff -q "$START_SRC" "$START_DST" >/dev/null 2>&1; then
        cp "$START_SRC" "$START_DST"
        chmod +x "$START_DST"
        echo "  Synced start launcher script"
    fi
fi

# Sync install.sh (setup script)
INSTALL_SRC="$SOURCE_DIR/../install.sh"
INSTALL_DST="$TARGET_PROJECT/install.sh"
if [ -f "$INSTALL_SRC" ]; then
    if [ ! -f "$INSTALL_DST" ] || ! diff -q "$INSTALL_SRC" "$INSTALL_DST" >/dev/null 2>&1; then
        cp "$INSTALL_SRC" "$INSTALL_DST"
        chmod +x "$INSTALL_DST"
        echo "  Synced install.sh setup script"
    fi
fi

echo "Beads workflow synced to $TARGET_PROJECT"
