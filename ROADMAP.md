# Roadmap

> Last updated: 2026-03-12

---

## Current: macOS (v2)

Event-driven Swift daemon. It subscribes to Spotify's track-change broadcasts and mutes within about 100ms, with a 2-second backup poll in case a broadcast is missed. Runs automatically at login via launchd. If the Xcode Command Line Tools aren't installed, the installer uses the v1 shell script instead.

**Known limitations:**
- Spotify announces an ad when it starts, not before, so a few milliseconds may be audible
- AppleScript support is controlled by Spotify and has broken in past updates — run `./update.sh` if you notice it stop working

---

## Maybe: Core Audio process tap (macOS 14.2+)

Mute Spotify's audio stream directly instead of moving its volume slider. There would be nothing to save or restore, but it needs the System Audio Recording permission.

---

## Coming: Windows

Per-process volume control so only Spotify is silenced — your other audio is never affected.

---

## Coming: Android

No root required. Uses Android's notification system to detect track changes.

---

## Out of scope: iOS

Apple's sandboxing model makes this not feasible without jailbreaking. No plans to support iOS.
