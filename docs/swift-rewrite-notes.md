# v2 Swift Rewrite — Contributor Notes

This document captures the context needed to implement the v2 Swift rewrite of `shall-not-pass`. The v1 shell script works but polls every 2 seconds. Swift with `DistributedNotificationCenter` eliminates polling entirely — the script only runs when Spotify broadcasts a track change.

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

Build command:
```bash
swiftc -o shall-not-pass main.swift
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
