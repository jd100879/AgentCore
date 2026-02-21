#!/usr/bin/env bash
# RU - Repo Updater wrapper
# Sync/clone GitHub repos in bulk, detect conflicts, JSON output for scripting.
# Usage: ./scripts/ru.sh                    # sync all repos
#        ./scripts/ru.sh --json             # machine-readable
#        ./scripts/ru.sh --non-interactive  # CI mode

set -uo pipefail

if command -v ru &>/dev/null; then
    exec ru "$@"
fi

for candidate in "$HOME/.local/bin/ru" "/opt/homebrew/bin/ru" "/usr/local/bin/ru"; do
    if [ -x "$candidate" ]; then
        exec "$candidate" "$@"
    fi
done

echo "❌ ru not found. Install it:" >&2
echo "   curl -fsSL 'https://raw.githubusercontent.com/Dicklesworthstone/repo_updater/main/install.sh' | bash" >&2
exit 2
