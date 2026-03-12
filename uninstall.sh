#!/usr/bin/env bash
# uninstall.sh — removes shall-not-pass and its LaunchAgent

set -euo pipefail

INSTALL_DIR="$HOME/.local/share/shall-not-pass"
PLIST_DEST="$HOME/Library/LaunchAgents/com.shall-not-pass.plist"

echo "Uninstalling shall-not-pass..."

# Unload the agent (ignore errors if it's not loaded)
if [ -f "$PLIST_DEST" ]; then
    launchctl unload "$PLIST_DEST" 2>/dev/null || true
    rm -f "$PLIST_DEST"
    echo "  Removed LaunchAgent plist."
else
    echo "  LaunchAgent plist not found — skipping unload."
fi

# Remove install directory
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo "  Removed $INSTALL_DIR"
else
    echo "  Install directory not found — skipping."
fi

echo ""
echo "shall-not-pass has been uninstalled."
echo "(Log file at ~/Library/Logs/shall-not-pass.log was left in place.)"
