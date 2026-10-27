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
