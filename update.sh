#!/usr/bin/env bash
# update.sh — pulls the latest version and restarts the daemon

set -euo pipefail

INSTALL_DIR="$HOME/.local/share/shall-not-pass"
PLIST_DEST="$HOME/Library/LaunchAgents/com.shall-not-pass.plist"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Verify we're in a git repo
if ! git -C "$SCRIPT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    echo "Error: $SCRIPT_DIR is not a git repository."
    echo "If you downloaded a zip, delete it and clone instead:"
    echo "  git clone https://github.com/andrewwoodruff/shall-not-pass.git"
    exit 1
fi

echo "Pulling latest version..."
git -C "$SCRIPT_DIR" pull

echo "Restarting daemon..."
launchctl unload "$PLIST_DEST" 2>/dev/null || true

# Copy updated script
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/shall-not-pass.sh" "$INSTALL_DIR/shall-not-pass.sh"
chmod +x "$INSTALL_DIR/shall-not-pass.sh"

# Re-expand plist template (picks up any plist changes in the update)
sed \
    -e "s|__INSTALL_DIR__|$INSTALL_DIR|g" \
    -e "s|__USERNAME__|$(whoami)|g" \
    "$SCRIPT_DIR/com.shall-not-pass.plist" > "$PLIST_DEST"

launchctl load -w "$PLIST_DEST"

echo ""
echo "shall-not-pass updated and restarted."
echo "  Log: tail -f ~/Library/Logs/shall-not-pass.log"
