#!/usr/bin/env bash
# shall-not-pass — silences Spotify ads without touching system volume
# https://github.com/andrewgwoodruff/shall-not-pass
#
# This file is the whole program. On start it builds the event-driven Swift
# daemon embedded at the bottom of this file (once per version, cached in
# ~/Library/Caches/shall-not-pass) and runs it. Without the Xcode Command Line
# Tools it falls back to the 2-second polling loop below.
#
# Every install and update path only ever copies this one file, so any
# version of install.sh or update.sh can install any version of the daemon.
#
# Usage: shall-not-pass.sh            run the daemon
#        shall-not-pass.sh --build    build the Swift daemon only (exit 1 if unavailable)
#        shall-not-pass.sh --source   print the embedded Swift source

set -euo pipefail

SELF="${BASH_SOURCE[0]}"
CACHE_DIR="$HOME/Library/Caches/shall-not-pass"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Print the embedded block between __NAME__ and __END_NAME__
embedded() {
    sed -n "/^__${1}__\$/,/^__END_${1}__\$/p" "$SELF" | sed '1d;$d'
}

# Build the Swift daemon if this version isn't cached yet; print its path.
build_swift() {
    if ! xcode-select -p >/dev/null 2>&1 || ! xcrun --find swiftc >/dev/null 2>&1; then
        # /usr/bin/swiftc exists even without the tools and would pop up an
        # install dialog, so check xcode-select first.
        log "Xcode Command Line Tools not found. Using the shell version (2s polling)." >&2
        log "For near-instant muting: run 'xcode-select --install', then restart shall-not-pass." >&2
        return 1
    fi

    local hash bin tmp
    hash=$({ embedded SWIFT; embedded INFO_PLIST; } | shasum -a 256 | cut -c1-12)
    bin="$CACHE_DIR/$hash/shall-not-pass"
    if [ -x "$bin" ]; then
        echo "$bin"
        return 0
    fi

    log "Building event-driven daemon..." >&2
    tmp=$(mktemp -d)
    embedded SWIFT > "$tmp/shall-not-pass.swift"
    embedded INFO_PLIST > "$tmp/Info.plist"
    # The embedded Info.plist supplies NSAppleEventsUsageDescription; without
    # it macOS can deny Apple Events from the binary without prompting.
    if xcrun swiftc -O -o "$tmp/shall-not-pass" "$tmp/shall-not-pass.swift" \
            -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$tmp/Info.plist" \
            >"$tmp/build.log" 2>&1 \
        && codesign --force --sign - --identifier com.shall-not-pass "$tmp/shall-not-pass" >>"$tmp/build.log" 2>&1; then
        rm -rf "$CACHE_DIR"
        mkdir -p "$CACHE_DIR/$hash"
        mv -f "$tmp/shall-not-pass" "$bin"
        rm -rf "$tmp"
        echo "$bin"
    else
        log "Build failed. Using the shell version (2s polling). Compiler output:" >&2
        tail -20 "$tmp/build.log" | sed 's/^/    /' >&2
        rm -rf "$tmp"
        return 1
    fi
}

case "${1:-}" in
    --build) build_swift >/dev/null; exit $? ;;
    --source) embedded SWIFT; exit 0 ;;
esac

if BIN=$(build_swift); then
    exec "$BIN"
fi

# ---------------------------------------------------------------------------
# Fallback: polling version (v1)
# ---------------------------------------------------------------------------

SAVED_VOLUME=50
AD_PLAYING=false
SPOTIFY_WAS_RUNNING=false
PERMISSION_WARNED=false
ERR_FILE="/tmp/shall-not-pass-$$.err"

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

exit 0

# ---------------------------------------------------------------------------
# Embedded files, read by embedded(). Bash never reaches them (exit above), and
# the quoted heredocs keep the file valid shell for bash -n and editors.
# ---------------------------------------------------------------------------

: <<'__END_INFO_PLIST__'
__INFO_PLIST__
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.shall-not-pass</string>
    <key>CFBundleName</key>
    <string>shall-not-pass</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>shall-not-pass lowers Spotify's volume during ads and restores it afterward.</string>
</dict>
</plist>
__END_INFO_PLIST__

: <<'__END_SWIFT__'
__SWIFT__
// shall-not-pass — silences Spotify ads without touching system volume
// https://github.com/andrewgwoodruff/shall-not-pass
//
// Event-driven: reacts to Spotify's PlaybackStateChanged broadcast within
// milliseconds, with a 2-second AppleScript poll as a safety net.
//
// Everything runs on the main thread (notifications, poll timer, launch/quit
// events, signals), so state transitions are strictly serialized.

import AppKit
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)

let spotifyBundleID = "com.spotify.client"
let playbackNotification = Notification.Name("com.spotify.client.PlaybackStateChanged")
let pollInterval: TimeInterval = 2
let pausedPollEvery = 5              // while paused, only poll every 5th tick (10s)
let restoreVerifyDelay: TimeInterval = 0.15
let defaultVolume = 50

let stateDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/shall-not-pass")
let stateFile = stateDir.appendingPathComponent("state.json")

func log(_ message: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    print("[\(formatter.string(from: Date()))] \(message)")
}

// MARK: - Spotify (AppleScript)

struct Snapshot {
    let isPlaying: Bool
    let trackID: String
    let volume: Int
}

enum ScriptError: Error {
    case notAuthorized
    case notRunning
    case other(String)
}

final class Spotify {
    private var cache: [String: NSAppleScript] = [:]

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: spotifyBundleID).isEmpty
    }

    // Any `tell application "Spotify"` launches Spotify if it's closed,
    // so every call is gated on isRunning.
    private func run(_ source: String) -> Result<NSAppleEventDescriptor, ScriptError> {
        guard isRunning else { return .failure(.notRunning) }
        let script: NSAppleScript
        if let cached = cache[source] {
            script = cached
        } else {
            guard let compiled = NSAppleScript(source: source) else {
                return .failure(.other("could not create script"))
            }
            var compileError: NSDictionary?
            compiled.compileAndReturnError(&compileError)
            cache[source] = compiled
            script = compiled
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error = error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            let message = error[NSAppleScript.errorMessage] as? String ?? "unknown error"
            switch code {
            case -1743: return .failure(.notAuthorized)
            // Only quiet if Spotify really quit; otherwise surface it so a
            // transient connection error is logged rather than swallowed.
            case -600 where !isRunning, -609 where !isRunning: return .failure(.notRunning)
            default: return .failure(.other("\(message) (\(code))"))
            }
        }
        return .success(result)
    }

    func snapshot() -> Result<Snapshot, ScriptError> {
        run("""
        tell application "Spotify" to return {player state as string, spotify url of current track, sound volume}
        """).map { list in
            Snapshot(
                isPlaying: list.atIndex(1)?.stringValue == "playing",
                trackID: list.atIndex(2)?.stringValue ?? "",
                volume: Int(list.atIndex(3)?.int32Value ?? -1)
            )
        }
    }

    func volume() -> Result<Int, ScriptError> {
        run("tell application \"Spotify\" to return sound volume").map { Int($0.int32Value) }
    }

    @discardableResult
    func setVolume(_ volume: Int) -> Result<Void, ScriptError> {
        run("tell application \"Spotify\" to set sound volume to \(volume)").map { _ in () }
    }
}

// MARK: - Persisted state

// Written before muting, deleted after a successful restore. If the daemon
// dies mid-ad (crash, kill, reboot), the next start restores the real volume
// instead of guessing.
struct PersistedState: Codable {
    var savedVolume: Int
}

func loadPersisted() -> PersistedState? {
    guard let data = try? Data(contentsOf: stateFile) else { return nil }
    return try? JSONDecoder().decode(PersistedState.self, from: data)
}

func savePersisted(_ state: PersistedState) {
    try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
    if let data = try? JSONEncoder().encode(state) {
        try? data.write(to: stateFile, options: .atomic)
    }
}

func clearPersisted() {
    try? FileManager.default.removeItem(at: stateFile)
}

// MARK: - State machine

enum Mode: Equatable {
    case idle
    case muted(savedVolume: Int)
    case userOverride      // user moved the slider during an ad; hands off until it ends
}

enum Source: String {
    case notification, poll, startup
}

func isAd(_ trackID: String) -> Bool { trackID.hasPrefix("spotify:ad:") }

final class Suppressor {
    private let spotify = Spotify()
    private var mode: Mode = .idle
    private var lastKnownPlaying = true
    // The volume the user chose. Spotify quantizes (set 85, read back 84), so
    // re-reading after each restore would drift the volume down every ad.
    private var userVolume: Int?
    private var pendingRestore: DispatchWorkItem?
    private var permissionWarned = false
    private var pollTick = 0

    init() {
        if let persisted = loadPersisted() {
            mode = .muted(savedVolume: persisted.savedVolume)
            log("Found saved volume \(persisted.savedVolume) from a previous run. Will restore when the interruption ends.")
        }
    }

    func start() {
        DistributedNotificationCenter.default().addObserver(
            forName: playbackNotification, object: nil, queue: .main
        ) { [weak self] note in
            self?.handleNotification(note.userInfo ?? [:])
        }

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard Self.isSpotify(note) else { return }
            log("Spotify launched. Now watching.")
            self?.poll(force: true)
        }
        workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard Self.isSpotify(note) else { return }
            self?.cancelPendingRestore()
            self?.permissionWarned = false
            if case .muted = self?.mode {
                // Spotify remembers volume 0 across launches; keep the saved
                // volume so it's restored once music plays again.
                log("Spotify closed during an interruption. Will restore volume when it's back.")
            } else {
                log("Spotify closed.")
            }
        }

        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in self?.poll() }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)

        log("shall-not-pass is watching. (event-driven, backup poll: \(Int(pollInterval))s)")
        if spotify.isRunning {
            log("Spotify detected. Now watching.")
            poll(force: true, source: .startup)
        }
    }

    private static func isSpotify(_ note: Notification) -> Bool {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        return app?.bundleIdentifier == spotifyBundleID
    }

    // MARK: Inputs

    private func handleNotification(_ info: [AnyHashable: Any]) {
        let trackID = info["Track ID"] as? String ?? ""
        let state = info["Player State"] as? String ?? ""
        lastKnownPlaying = state == "Playing"
        evaluate(trackID: trackID, isPlaying: lastKnownPlaying, volume: nil, source: .notification)
    }

    private func poll(force: Bool = false, source: Source = .poll) {
        guard spotify.isRunning else { return }
        pollTick += 1
        // Nothing changes while paused, and resuming sends a notification;
        // still check occasionally in case that notification is missed.
        if !force && !lastKnownPlaying && pollTick % pausedPollEvery != 0 { return }

        switch spotify.snapshot() {
        case .success(let snap):
            permissionWarned = false
            lastKnownPlaying = snap.isPlaying
            if mode == .idle { noteVolume(snap.volume) }
            evaluate(trackID: snap.trackID, isPlaying: snap.isPlaying, volume: snap.volume, source: source)
        case .failure(let error):
            handle(error)
        }
    }

    private func noteVolume(_ volume: Int) {
        guard volume > 0 else { return }
        if let known = userVolume, abs(volume - known) <= 1 { return }
        userVolume = volume
    }

    // MARK: Transitions

    private func evaluate(trackID: String, isPlaying: Bool, volume: Int?, source: Source) {
        if isAd(trackID) {
            cancelPendingRestore()
            switch mode {
            case .idle:
                mute(source: source)
            case .muted:
                // Volume should be 0 while muted. Anything else means the user
                // turned it up on purpose; respect that until the ad ends.
                if let volume = volume, volume > 1 {
                    log("Volume changed to \(volume) during interruption. Respecting your change until it ends.")
                    mode = .userOverride
                    clearPersisted()
                }
            case .userOverride:
                break
            }
            return
        }

        // Empty track ID = transitional or stopped state; never act on it.
        guard !trackID.isEmpty else { return }

        switch mode {
        case .idle:
            break
        case .userOverride:
            mode = .idle
            log("Interruption ended.")
        case .muted:
            if isPlaying && pendingRestore == nil {
                scheduleRestore(source: source)
            }
        }
    }

    private func mute(source: Source) {
        let current: Int
        switch spotify.volume() {
        case .success(let volume): current = volume
        case .failure(let error): handle(error); return
        }

        noteVolume(current)
        let saved = userVolume ?? defaultVolume
        if current <= 0 {
            log("Volume was already 0 (possible stale mute). Will restore to \(saved).")
        }

        // Persist first, so a crash between here and setVolume can't lose it.
        savePersisted(PersistedState(savedVolume: saved))
        if case .failure(let error) = spotify.setVolume(0) {
            handle(error)
            clearPersisted()
            return
        }
        mode = .muted(savedVolume: saved)
        if source == .poll {
            log("Interruption detected by backup poll (notification was missed). Muted. (saved volume: \(saved))")
        } else {
            log("Interruption detected. Muted. (saved volume: \(saved))")
        }
    }

    // Mute is instant; restore waits briefly and re-checks, because Spotify can
    // emit a non-ad state between back-to-back ads.
    private func scheduleRestore(source: Source) {
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.pendingRestore = nil
            self.verifyAndRestore(source: source)
        }
        pendingRestore = work
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreVerifyDelay, execute: work)
    }

    private func cancelPendingRestore() {
        pendingRestore?.cancel()
        pendingRestore = nil
    }

    private func verifyAndRestore(source: Source) {
        guard case .muted(let saved) = mode else { return }
        switch spotify.snapshot() {
        case .success(let snap):
            guard snap.isPlaying, !snap.trackID.isEmpty, !isAd(snap.trackID) else { return }
            restore(to: saved, source: source)
        case .failure(let error):
            handle(error)
        }
    }

    // Sets the volume once and trusts the result (within Spotify's ±1
    // quantization). A failure leaves mode as .muted, so the next poll retries.
    @discardableResult
    private func restore(to saved: Int, source: Source) -> Bool {
        if case .failure(let error) = spotify.setVolume(saved) {
            handle(error)
            return false
        }
        if case .success(let actual) = spotify.volume(), abs(actual - saved) > 1 {
            log("Volume restore failed (expected \(saved), got \(actual)). Will retry.")
            return false
        }
        mode = .idle
        userVolume = saved
        clearPersisted()
        if source == .poll {
            log("Interruption ended (detected by backup poll; notification was missed). Volume restored to \(saved).")
        } else {
            log("Interruption ended. Volume restored to \(saved).")
        }
        return true
    }

    private func handle(_ error: ScriptError) {
        switch error {
        case .notRunning:
            break
        case .notAuthorized:
            if !permissionWarned {
                log("ERROR: Automation permission not granted. shall-not-pass cannot control Spotify.")
                log("Fix: System Settings -> Privacy & Security -> Automation")
                log("     Enable shall-not-pass to control Spotify, then restart the daemon.")
                permissionWarned = true
            }
        case .other(let message):
            log("AppleScript error: \(message)")
        }
    }

    func shutdown() {
        log("Shutting down. Restoring volume...")
        cancelPendingRestore()
        if case .muted(let saved) = mode {
            // If this fails (or Spotify isn't running), the saved volume stays
            // on disk and the next start restores it.
            var restored = false
            for attempt in 1...3 where !restored {
                if attempt > 1 { usleep(200_000) }
                restored = restore(to: saved, source: .notification)
            }
            if !restored {
                log("Could not restore volume before exiting. It will be restored to \(saved) on next start.")
            }
        }
        log("Goodbye.")
        exit(0)
    }
}

// MARK: - Main

// Keep macOS from coalescing or throttling the poll timer (App Nap).
let activity = ProcessInfo.processInfo.beginActivity(
    options: [.userInitiatedAllowingIdleSystemSleep],
    reason: "Watching Spotify for interruptions"
)

let suppressor = Suppressor()

var signalSources: [DispatchSourceSignal] = []
for sig in [SIGTERM, SIGINT] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler { suppressor.shutdown() }
    source.resume()
    signalSources.append(source)
}

suppressor.start()
RunLoop.main.run()
__END_SWIFT__
