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

SRC_DIR="$(mktemp -d)"
trap 'rm -rf "$SRC_DIR"' EXIT

SOURCES=(shall-not-pass.swift Info.plist shall-not-pass.sh uninstall.sh com.shall-not-pass.plist)
if [ -f "$SCRIPT_DIR/shall-not-pass.swift" ]; then
    # Running from a git clone — use local files
    for f in "${SOURCES[@]}"; do cp "$SCRIPT_DIR/$f" "$SRC_DIR/$f"; done
else
    # Running via curl | bash — download files from GitHub
    for f in "${SOURCES[@]}"; do curl -fsSL "$REPO_URL/$f" -o "$SRC_DIR/$f"; done
fi

# Unload any existing agent before replacing files, so reinstalls work cleanly
launchctl unload "$PLIST_DEST" 2>/dev/null || true

# Prefer the event-driven Swift daemon (near-instant muting). Fall back to the
# polling shell script if the Xcode Command Line Tools aren't installed.
# Check xcode-select first: /usr/bin/swiftc exists even without the tools and
# would pop up an install dialog.
BUILT=false
if xcode-select -p >/dev/null 2>&1 && xcrun --find swiftc >/dev/null 2>&1; then
    echo "Building..."
    if xcrun swiftc -O -o "$SRC_DIR/shall-not-pass" "$SRC_DIR/shall-not-pass.swift" \
        -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$SRC_DIR/Info.plist" \
        && codesign --force --sign - --identifier com.shall-not-pass "$SRC_DIR/shall-not-pass"; then
        BUILT=true
    else
        echo "Build failed. Falling back to the shell script version."
    fi
else
    echo "Xcode Command Line Tools not found. Installing the shell script version (2s polling)."
    echo "For near-instant muting, run 'xcode-select --install' and re-run this installer."
fi

if [ "$BUILT" = true ]; then
    mv -f "$SRC_DIR/shall-not-pass" "$INSTALL_DIR/shall-not-pass"
else
    # The script has a shebang, so the LaunchAgent runs it the same way
    cp "$SRC_DIR/shall-not-pass.sh" "$INSTALL_DIR/shall-not-pass"
fi
rm -f "$INSTALL_DIR/shall-not-pass.sh"   # left over from older versions
cp "$SRC_DIR/uninstall.sh" "$INSTALL_DIR/uninstall.sh"
chmod +x "$INSTALL_DIR/shall-not-pass" "$INSTALL_DIR/uninstall.sh"

sed \
    -e "s|__INSTALL_DIR__|$INSTALL_DIR|g" \
    -e "s|__USERNAME__|$(whoami)|g" \
    "$SRC_DIR/com.shall-not-pass.plist" > "$PLIST_DEST"

echo ""
if [ "$BUILT" = true ]; then
    # The daemon controls Spotify as itself, so it asks for permission itself
    # once it starts (or the first time Spotify is open).
    echo "Automation permission is required for shall-not-pass to work."
    echo "macOS will ask: \"shall-not-pass\" wants access to control \"Spotify\". Click OK."
    echo "If Spotify is not open, the prompt will appear the first time you open it."
    echo "If you dismissed it: System Settings -> Privacy & Security -> Automation"
    echo "  -> enable shall-not-pass to control Spotify."
else
    # Request Automation permission BEFORE starting the daemon.
    # If both request it simultaneously, macOS shows two dialogs.
    # Doing it here first means the daemon starts with permission already granted.
    echo "Requesting Automation permission..."
    echo "(macOS may show a dialog. Click OK to allow your terminal to control Spotify.)"
    echo ""
    if osascript -e 'tell application "Spotify" to get sound volume' >/dev/null 2>&1; then
        echo "Permission granted."
    else
        echo "IMPORTANT: Automation permission is required for shall-not-pass to work."
        echo ""
        echo "If Spotify is not open, open it and you will be prompted automatically."
        echo "If you dismissed the dialog, grant permission manually:"
        echo "  System Settings -> Privacy & Security -> Automation"
        echo "  Enable your terminal app to control Spotify."
    fi
fi

launchctl load -w "$PLIST_DEST"

echo ""
echo "  Log:       tail -f $LOG_FILE"
echo "  Status:    launchctl list | grep shall-not-pass"
echo "  Update:    curl -fsSL $REPO_URL/install.sh | bash"
echo "  Uninstall: $INSTALL_DIR/uninstall.sh"
