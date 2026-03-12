#!/usr/bin/env bash
# shall-not-pass — silences Spotify ads without touching system volume
# https://github.com/andrewgwoodruff/shall-not-pass

set -euo pipefail

SAVED_VOLUME=50
AD_PLAYING=false
SPOTIFY_WAS_RUNNING=false
PERMISSION_WARNED=false
ERR_FILE="/tmp/shall-not-pass-$$.err"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

restore_volume() {
    if [ "$AD_PLAYING" = true ]; then
        osascript -e "tell application \"Spotify\" to set sound volume to $SAVED_VOLUME" 2>/dev/null || true
        log "Volume restored to $SAVED_VOLUME"
        AD_PLAYING=false
    fi
}

cleanup() {
    log "Shutting down. Restoring volume..."
    restore_volume
    rm -f "$ERR_FILE"
    log "Goodbye."
    exit 0
}

trap cleanup SIGTERM SIGINT

log "shall-not-pass is watching. (poll interval: 2s)"

while true; do
    # Check if Spotify is running
    if ! pgrep -x Spotify >/dev/null 2>&1; then
        if [ "$SPOTIFY_WAS_RUNNING" = true ]; then
            log "Spotify closed. Resetting state."
            AD_PLAYING=false
            SPOTIFY_WAS_RUNNING=false
            PERMISSION_WARNED=false
        fi
        sleep 5
        continue
    fi

    if [ "$SPOTIFY_WAS_RUNNING" = false ]; then
        log "Spotify detected. Now watching."
        SPOTIFY_WAS_RUNNING=true
    fi

    CURRENT_URL=$(osascript -e 'tell application "Spotify" to get spotify url of current track' 2>"$ERR_FILE" || echo "")

    # Check for Automation permission denial
    if grep -qi "not authorized\|1743" "$ERR_FILE" 2>/dev/null; then
        if [ "$PERMISSION_WARNED" = false ]; then
            log "ERROR: Automation permission not granted. shall-not-pass cannot control Spotify."
            log "Fix: System Settings -> Privacy & Security -> Automation"
            log "     Enable your terminal app to control Spotify, then restart the daemon."
            PERMISSION_WARNED=true
        fi
        sleep 5
        continue
    fi

    PERMISSION_WARNED=false

    if [[ "$CURRENT_URL" == spotify:ad:* ]]; then
        if [ "$AD_PLAYING" = false ]; then
            SAVED_VOLUME=$(osascript -e 'tell application "Spotify" to get sound volume' 2>/dev/null || echo "50")
            osascript -e 'tell application "Spotify" to set sound volume to 0' 2>/dev/null || true
            AD_PLAYING=true
            log "Interruption detected. Muted. (saved volume: $SAVED_VOLUME)"
        fi
    else
        if [ "$AD_PLAYING" = true ]; then
            restore_volume
            log "Interruption ended. Volume restored."
        fi
    fi

    sleep 2
done
