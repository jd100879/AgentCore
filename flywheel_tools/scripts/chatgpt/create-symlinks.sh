#!/bin/bash
# Create symlinks for all migrated scripts

FT="../flywheel_tools/scripts"

# Core scripts
ln -sf "$FT/core/agent-runner.sh" .
ln -sf "$FT/core/next-bead.sh" .

# Beads scripts
ln -sf "$FT/beads/br-create.sh" .
ln -sf "$FT/beads/br-start-work.sh" .
ln -sf "$FT/beads/br-wrapper.sh" .
ln -sf "$FT/beads/bv-claim.sh" .
ln -sf "$FT/beads/log-bead-activity.sh" .
ln -sf "$FT/beads/bead-stale-monitor.sh" .

# Terminal scripts
ln -sf "$FT/terminal/terminal-inject.sh" .
ln -sf "$FT/terminal/arrange-panes.sh" .
ln -sf "$FT/terminal/cleanup-after-pane-removal.sh" .
ln -sf "$FT/terminal/renumber-panes.sh" .

# Dev tools
ln -sf "$FT/dev/hook-bypass.sh" .

# Deprecated hooks (now in global ~/.claude/hooks/)
ln -sf "$FT/deprecated/hooks-moved-to-global-2026-02-10/session-start-hook.sh" .
ln -sf "$FT/deprecated/hooks-moved-to-global-2026-02-10/session-stop-hook.sh" .
ln -sf "$FT/deprecated/hooks-moved-to-global-2026-02-10/pre-edit-check-hook.sh" .
ln -sf "$FT/deprecated/hooks-moved-to-global-2026-02-10/pre-edit-check.sh" .
ln -sf "$FT/deprecated/hooks-moved-to-global-2026-02-10/pre-bash-bead-check-hook.sh" .
ln -sf "$FT/deprecated/hooks-moved-to-global-2026-02-10/post-bash-bead-track-hook.sh" .
ln -sf "$FT/deprecated/hooks-moved-to-global-2026-02-10/post-bead-close-hook.sh" .

echo "✓ Symlinks created"
