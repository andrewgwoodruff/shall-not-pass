#!/usr/bin/env bash
# shall-not-pass — silences Spotify ads without touching system volume
# https://github.com/andrewwoodruff/shall-not-pass

set -euo pipefail

SAVED_VOLUME=50
AD_PLAYING=false
SPOTIFY_WAS_RUNNING=false

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
    log "Shutting down — restoring volume..."
    restore_volume
    log "Goodbye."
    exit 0
}

trap cleanup SIGTERM SIGINT

log "shall-not-pass is watching. (poll interval: 2s)"

while true; do
    # Check if Spotify is running
    if ! pgrep -x Spotify >/dev/null 2>&1; then
        if [ "$SPOTIFY_WAS_RUNNING" = true ]; then
            log "Spotify closed — resetting state."
            AD_PLAYING=false
            SPOTIFY_WAS_RUNNING=false
        fi
        sleep 5
        continue
    fi

    if [ "$SPOTIFY_WAS_RUNNING" = false ]; then
        log "Spotify detected — now watching for ads."
        SPOTIFY_WAS_RUNNING=true
    fi

    CURRENT_URL=$(osascript -e 'tell application "Spotify" to get spotify url of current track' 2>/dev/null || echo "")

    if [[ "$CURRENT_URL" == spotify:ad:* ]]; then
        if [ "$AD_PLAYING" = false ]; then
            SAVED_VOLUME=$(osascript -e 'tell application "Spotify" to get sound volume' 2>/dev/null || echo "50")
            osascript -e 'tell application "Spotify" to set sound volume to 0' 2>/dev/null || true
            AD_PLAYING=true
            log "Ad detected — muted. (saved volume: $SAVED_VOLUME)"
        fi
    else
        if [ "$AD_PLAYING" = true ]; then
            restore_volume
            log "Ad ended — volume restored."
        fi
    fi

    sleep 2
done
