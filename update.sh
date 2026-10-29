#!/usr/bin/env bash
# update.sh — pulls the latest version and restarts the daemon
#
# Works from either place:
#   - a git clone (manual install): pulls, then reinstalls from the clone
#   - ~/.local/share/shall-not-pass/update.sh: updates the same way this
#     machine was installed, as recorded in install-info

set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/andrewgwoodruff/shall-not-pass/main"
INSTALL_DIR="$HOME/.local/share/shall-not-pass"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$SCRIPT_DIR" = "$INSTALL_DIR" ]; then
    # Installed copy — update the same way this machine was installed
    METHOD="$(sed -n 's/^method=//p' "$INSTALL_DIR/install-info" 2>/dev/null || true)"
    SOURCE="$(sed -n 's/^source=//p' "$INSTALL_DIR/install-info" 2>/dev/null || true)"

    if [ "$METHOD" = manual ] && [ -x "$SOURCE/update.sh" ]; then
        echo "Manual install: updating from the clone at $SOURCE"
        exec "$SOURCE/update.sh"
    fi
    if [ "$METHOD" = manual ]; then
        echo "This machine was installed from a clone at $SOURCE, which no longer exists."
        echo "Updating from GitHub instead."
    else
        echo "Quick install: updating from GitHub"
    fi
    curl -fsSL "$REPO_URL/install.sh" | bash
    exit 0
fi

# Verify we're in a git repo
if ! git -C "$SCRIPT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    echo "Error: $SCRIPT_DIR is not a git repository."
    echo "If you downloaded a zip, delete it and clone instead:"
    echo "  git clone https://github.com/andrewgwoodruff/shall-not-pass.git"
    exit 1
fi

echo "Pulling latest version..."
git -C "$SCRIPT_DIR" pull

# install.sh is read fresh from the updated clone, so changes to the install
# process take effect on this same run.
"$SCRIPT_DIR/install.sh"

echo ""
echo "shall-not-pass updated and restarted."
echo "  Log: tail -f ~/Library/Logs/shall-not-pass.log"
