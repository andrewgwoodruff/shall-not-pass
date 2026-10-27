# v2 Swift Rewrite — Contributor Notes

This document captures the context needed to implement the v2 Swift rewrite of `shall-not-pass`. The v1 shell script works but polls every 2 seconds. Swift with `DistributedNotificationCenter` eliminates polling entirely — the script only runs when Spotify broadcasts a track change.

> **Status:** implemented in [`shall-not-pass.swift`](../shall-not-pass.swift). The sections below are the original research notes. See "Implementation notes" at the end for how the daemon avoids races.

---

## Why Swift for v2

| | v1 (Shell) | v2 (Swift) |
|---|---|---|
| Idle CPU | ~0.1% (poll every 2s) | ~0% (event-driven) |
| Detection latency | 0–2 seconds | <100ms |
| Dependencies | None | Xcode CLI tools to build |
| Binary size | ~2KB | ~100KB |
| Distribution | Single script | Compiled binary or app bundle |

The shell script is the right v1 — zero dependencies, auditable, easy to install. Swift is the right v2 once the project has users who expect polish.

---

## Key macOS API: DistributedNotificationCenter

Spotify broadcasts `com.spotify.client.PlaybackStateChanged` on every track change (including ad transitions). Subscribe in Swift:

```swift
import Foundation

DistributedNotificationCenter.default().addObserver(
    forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
    object: nil,
    queue: nil
) { notification in
    checkAndMute()
}
```

**Critical:** You must call `RunLoop.main.run()` at the end of your `main.swift` (or equivalent) to keep the process alive for notifications. Without this, the CLI tool exits immediately.

```swift
// main.swift — keep the run loop alive
RunLoop.main.run()
```

---

## AppleScript from Swift

Use `NSAppleScript` to query and control Spotify:

```swift
import Foundation

func runAppleScript(_ source: String) -> String? {
    var error: NSDictionary?
    let script = NSAppleScript(source: source)
    let result = script?.executeAndReturnError(&error)
    if let error = error {
        // Handle or log
        return nil
    }
    return result?.stringValue
}

// Detect ad
let url = runAppleScript("tell application \"Spotify\" to get spotify url of current track")
let isAd = url?.hasPrefix("spotify:ad:") ?? false

// Mute / restore
runAppleScript("tell application \"Spotify\" to set sound volume to 0")
runAppleScript("tell application \"Spotify\" to set sound volume to \(savedVolume)")
```

---

## Build Requirements

- Xcode Command Line Tools: `xcode-select --install`
- macOS 12+ deployment target
- No third-party dependencies needed for v2 core functionality

Build command (what `install.sh` runs). The embedded Info.plist supplies `NSAppleEventsUsageDescription`. Without it, macOS may reject Apple Events from the binary without ever showing a prompt:
```bash
swiftc -O -o shall-not-pass shall-not-pass.swift \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist
codesign --force --sign - --identifier com.shall-not-pass shall-not-pass
```

---

## Notarization Path

For distribution beyond `git clone`:

1. Enroll in Apple Developer Program ($99/year)
2. Build with Hardened Runtime enabled: `swiftc -O -o shall-not-pass main.swift` + Xcode signing config
3. Submit to Apple notarization: `xcrun notarytool submit`
4. Staple the ticket: `xcrun staple`

Notarization is required for Gatekeeper to allow the binary to run without a user override (`xattr -d com.apple.quarantine`). For early adopters, the quarantine workaround is acceptable. For broader distribution, notarize.

---

## Automation Entitlement

AppleScript control of Spotify requires the `com.apple.security.automation.apple-events` entitlement. Add to your `.entitlements` file:

```xml
<key>com.apple.security.automation.apple-events</key>
<true/>
```

Without this, the app will be blocked by macOS when running with Hardened Runtime.

---

## CPU Comparison (Reference)

The v1 shell script on Apple Silicon:
- `osascript` cold start: ~30ms per invocation
- 2 invocations per poll, every 2 seconds → ~30ms CPU per 2 seconds → ~1.5% at worst, typically <0.1% in practice

Swift with `DistributedNotificationCenter`:
- Zero CPU between track changes
- `NSAppleScript` execute: ~15ms per invocation
- Total: 2–3 invocations per track change, which happens a few times per hour

The real-world difference is minimal on modern hardware. The Swift rewrite is more about correctness and latency than measurable battery impact.

---

## Implementation notes

**Notification payload** (checked on Spotify 1.2.98, macOS 26): `userInfo` includes `Track ID` (e.g. `spotify:track:…`, `spotify:ad:…`) and `Player State` (`Playing` / `Paused`). Detection uses these values directly, with no AppleScript call.

**Serialization.** Every input (distributed notification, 2s poll timer, NSWorkspace launch/quit, SIGTERM/SIGINT through `DispatchSource`) is handled on the main thread. Transitions can never overlap.

**State machine.** `idle → muted(savedVolume) → idle`, plus `userOverride`:
- *Mute immediately* when an ad ID is seen. The saved volume is written to `~/Library/Application Support/shall-not-pass/state.json` before muting.
- *Restore carefully.* Restore only for a non-empty, non-ad ID while `Playing`, then wait 150ms and check again through AppleScript. A new ad cancels a pending restore. This covers the gap Spotify can show between back-to-back ads.
- *Respect the user.* If the volume is above 0 while muted, the user turned it up. Stop managing it until the ad ends.
- *Survive crashes and quits.* On startup, a leftover `state.json` means the daemon died mid-ad, and the volume is restored once music plays. If Spotify quits mid-ad, the saved volume is kept, since Spotify remembers 0 across launches.

**Volume quantization.** Spotify rounds the volume (set 85, read back 84). The daemon remembers the volume the user chose and ignores ±1 differences, so it doesn't lower the volume one step per ad.

**Backup poll.** It runs every 2s while playing and every 10s while paused. It never calls AppleScript when Spotify isn't running, because `tell application` would launch it. It follows the same mute and restore rules, and logs when it catches a transition the notification missed.

**Throttling.** `ProcessInfo.beginActivity` and `ProcessType=Interactive` in the LaunchAgent stop macOS from delaying the timer.

