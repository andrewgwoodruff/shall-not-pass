#!/usr/bin/env bash
# update.sh — pulls the latest version and restarts the daemon

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Verify we're in a git repo
if ! git -C "$SCRIPT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    echo "Error: $SCRIPT_DIR is not a git repository."
    echo "If you downloaded a zip, delete it and clone instead:"
    echo "  git clone https://github.com/andrewgwoodruff/shall-not-pass.git"
    exit 1
fi

echo "Pulling latest version..."
git -C "$SCRIPT_DIR" pull

# install.sh builds, copies files, re-expands the plist and restarts the daemon
"$SCRIPT_DIR/install.sh"

echo ""
echo "shall-not-pass updated and restarted."
