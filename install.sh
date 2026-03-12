#!/usr/bin/env bash
# install.sh — installs shall-not-pass as a macOS LaunchAgent

set -euo pipefail

if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: shall-not-pass currently supports macOS only."
    echo "See ROADMAP.md for Windows and Android plans."
    exit 1
fi

INSTALL_DIR="$HOME/.local/share/shall-not-pass"
PLIST_DEST="$HOME/Library/LaunchAgents/com.shall-not-pass.plist"
LOG_FILE="$HOME/Library/Logs/shall-not-pass.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing shall-not-pass..."

# Create install directory and copy script
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/shall-not-pass.sh" "$INSTALL_DIR/shall-not-pass.sh"
chmod +x "$INSTALL_DIR/shall-not-pass.sh"

# Expand plist template and write to LaunchAgents
mkdir -p "$HOME/Library/LaunchAgents"
sed \
    -e "s|__INSTALL_DIR__|$INSTALL_DIR|g" \
    -e "s|__USERNAME__|$(whoami)|g" \
    "$SCRIPT_DIR/com.shall-not-pass.plist" > "$PLIST_DEST"

# Load the agent
launchctl load -w "$PLIST_DEST"

echo ""
echo "shall-not-pass installed and running."
echo ""
echo "  Log:    tail -f $LOG_FILE"
echo "  Status: launchctl list | grep shall-not-pass"
echo ""
echo "Note: On first run, macOS may prompt for Automation permission."
echo "If prompted, open System Settings → Privacy & Security → Automation"
echo "and allow your terminal to control Spotify."
