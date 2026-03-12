#!/usr/bin/env bash
# install.sh — installs shall-not-pass as a macOS LaunchAgent
# Works whether run from a git clone or piped via curl | bash

set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/andrewwoodruff/shall-not-pass/main"
INSTALL_DIR="$HOME/.local/share/shall-not-pass"
PLIST_DEST="$HOME/Library/LaunchAgents/com.shall-not-pass.plist"
LOG_FILE="$HOME/Library/Logs/shall-not-pass.log"

# BASH_SOURCE is empty when piped via curl | bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" 2>/dev/null && pwd || echo "")"

if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: shall-not-pass currently supports macOS only."
    echo "See ROADMAP.md for Windows and Android plans."
    exit 1
fi

echo "Installing shall-not-pass..."

mkdir -p "$INSTALL_DIR"
mkdir -p "$HOME/Library/LaunchAgents"

if [ -f "$SCRIPT_DIR/shall-not-pass.sh" ]; then
    # Running from a git clone — use local files
    cp "$SCRIPT_DIR/shall-not-pass.sh" "$INSTALL_DIR/shall-not-pass.sh"
    cp "$SCRIPT_DIR/uninstall.sh" "$INSTALL_DIR/uninstall.sh"
    sed \
        -e "s|__INSTALL_DIR__|$INSTALL_DIR|g" \
        -e "s|__USERNAME__|$(whoami)|g" \
        "$SCRIPT_DIR/com.shall-not-pass.plist" > "$PLIST_DEST"
else
    # Running via curl | bash — download files from GitHub
    curl -fsSL "$REPO_URL/shall-not-pass.sh" -o "$INSTALL_DIR/shall-not-pass.sh"
    curl -fsSL "$REPO_URL/uninstall.sh" -o "$INSTALL_DIR/uninstall.sh"
    curl -fsSL "$REPO_URL/com.shall-not-pass.plist" | \
        sed \
            -e "s|__INSTALL_DIR__|$INSTALL_DIR|g" \
            -e "s|__USERNAME__|$(whoami)|g" \
        > "$PLIST_DEST"
fi

chmod +x "$INSTALL_DIR/shall-not-pass.sh" "$INSTALL_DIR/uninstall.sh"

# Load the agent
launchctl load -w "$PLIST_DEST"

echo ""
echo "shall-not-pass installed and running."
echo ""
echo "  Log:      tail -f $LOG_FILE"
echo "  Status:   launchctl list | grep shall-not-pass"
echo "  Update:   curl -fsSL $REPO_URL/install.sh | bash"
echo "  Uninstall: $INSTALL_DIR/uninstall.sh"
echo ""
echo "Note: On first run, macOS may prompt for Automation permission."
echo "If prompted, open System Settings → Privacy & Security → Automation"
echo "and allow your terminal to control Spotify."
