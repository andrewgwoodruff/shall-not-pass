#!/usr/bin/env bash
# install.sh — installs shall-not-pass as a macOS LaunchAgent
# Works whether run from a git clone or piped via curl | bash

set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/andrewgwoodruff/shall-not-pass/main"
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

# Request Automation permission now, while the user is watching.
# macOS will show a dialog asking to allow this terminal to control Spotify.
# The daemon cannot function without this — better to surface it here than
# have it silently fail in the background.
echo ""
echo "Requesting Automation permission..."
echo "(macOS may show a dialog. Click OK to allow your terminal to control Spotify.)"
echo ""
if osascript -e 'tell application "Spotify" to get sound volume' >/dev/null 2>&1; then
    echo "Permission granted. shall-not-pass is ready."
else
    echo "IMPORTANT: Automation permission is required for shall-not-pass to work."
    echo ""
    echo "If Spotify is not open, open it and you will be prompted automatically."
    echo "If you dismissed the dialog, grant permission manually:"
    echo "  System Settings -> Privacy & Security -> Automation"
    echo "  Enable your terminal app to control Spotify."
    echo ""
    echo "The daemon is running and will work as soon as permission is granted."
fi

echo ""
echo "  Log:       tail -f $LOG_FILE"
echo "  Status:    launchctl list | grep shall-not-pass"
echo "  Update:    curl -fsSL $REPO_URL/install.sh | bash"
echo "  Uninstall: $INSTALL_DIR/uninstall.sh"
