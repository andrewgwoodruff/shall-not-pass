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
        local current_vol diff
        current_vol=$(osascript -e 'tell application "Spotify" to get sound volume' 2>/dev/null || echo "-1")
        # Spotify quantizes volume internally; accept ±1 to avoid an infinite retry loop
        diff=$(( current_vol - SAVED_VOLUME ))
        [ "$diff" -lt 0 ] && diff=$(( -diff ))
        if [ "$diff" -le 1 ]; then
            log "Volume restored to $current_vol"
            AD_PLAYING=false
        else
            log "Volume restore failed (expected $SAVED_VOLUME, got $current_vol). Will retry next poll."
        fi
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
            if [ "$SAVED_VOLUME" = "0" ]; then
                log "Captured volume was 0 (possible stale mute). Defaulting to 50."
                SAVED_VOLUME=50
            fi
            osascript -e 'tell application "Spotify" to set sound volume to 0' 2>/dev/null || true
            AD_PLAYING=true
            log "Interruption detected. Muted. (saved volume: $SAVED_VOLUME)"
        fi
    else
        if [ "$AD_PLAYING" = true ]; then
            restore_volume
            if [ "$AD_PLAYING" = false ]; then
                log "Interruption ended. Volume restored."
            fi
        fi
    fi

    sleep 2
done
