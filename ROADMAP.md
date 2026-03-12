# Roadmap

> Last updated: 2026-03-12

---

## Current: macOS (v1)

Shell script daemon that silences audio interruptions in Spotify via AppleScript. Runs automatically at login via launchd. Zero dependencies.

**Known limitations:**
- ~2 second detection latency before muting kicks in
- AppleScript support is controlled by Spotify and has broken in past updates — run `./update.sh` if you notice it stop working

---

## Coming: macOS v2

A rewrite that eliminates the detection latency by subscribing to Spotify's track-change events instead of polling. The mute will be near-instant. No change to how you install or use it.

---

## Coming: Windows

Per-process volume control so only Spotify is silenced — your other audio is never affected.

---

## Coming: Android

No root required. Uses Android's notification system to detect track changes.

---

## Out of scope: iOS

Apple's sandboxing model makes this not feasible without jailbreaking. No plans to support iOS.
