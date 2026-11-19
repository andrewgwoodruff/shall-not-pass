#!/usr/bin/env bash
# install.sh — installs shall-not-pass on macOS
#
# This stays at the repo root so the published curl | bash command never
# changes, and so installs from before macos/ existed keep updating. The real
# installer is macos/install.sh.

set -euo pipefail

REPO_URL="${SHALL_NOT_PASS_REPO_URL:-https://raw.githubusercontent.com/andrewgwoodruff/shall-not-pass/main}"

# BASH_SOURCE is empty when piped via curl | bash. Only a script run from a
# file has a directory of its own.
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/macos/install.sh" ]; then
    # Running from a git clone
    exec "$SCRIPT_DIR/macos/install.sh"
fi

curl -fsSL "$REPO_URL/macos/install.sh" | bash
