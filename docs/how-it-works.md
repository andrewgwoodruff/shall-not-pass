# How it works

`shall-not-pass` watches the Spotify desktop app through its public AppleScript interface and the notifications Spotify broadcasts to macOS. It never modifies Spotify, never touches the network, and needs no admin rights. The only thing it changes is Spotify's own volume slider.

Measurements below are from Spotify 1.2.98 and 1.3.6 on macOS 26.6 (Apple Silicon).

---

## What Spotify tells us, and what it doesn't

**Notifications.** Spotify posts `com.spotify.client.PlaybackStateChanged` to the distributed notification center. Its `userInfo` includes `Track ID` (`spotify:track:…`, `spotify:ad:…`), `Player State` (`Playing` / `Paused`), `Duration` (ms) and `Playback Position` (s).

A real interruption was recorded with a probe that logged every notification and polled every 500ms:

| Transition | Notification sent? |
|---|---|
| Music → interruption | **No** |
| Interruption → interruption (back to back) | **No** |
| Interruption → music | Yes, with the new track's ID |
| Pause / play / skip between tracks | Yes |

So a notification is enough to know when to **restore** the volume, but not when to **mute**.

**AppleScript.** `spotify url of current track` reliably reports `spotify:ad:…` (Spotify's own ID prefix) during interruptions. Every Apple Event to Spotify takes about **16.6ms**, one 60Hz frame, whatever the property. Spotify answers once per UI frame, so a script that reads five properties takes about 84ms. The fast path therefore reads one property at a time.

---

## Detecting the start of an interruption

Interruptions only start where a track ends. The daemon:

1. **Predicts the track end** from `Duration` and `Playback Position`. These come from each notification, and from a full AppleScript snapshot every 2 seconds, so seeks and skips correct the prediction quickly.
2. **Watches the boundary.** Starting 0.75s before the predicted end, it reads `spotify url of current track` every 50ms (one frame each) until the track changes, or until 2.5s past the predicted end.
3. **Mutes in a single script** that reads the current volume and sets it to 0 (two frames).

Expected time from interruption start to silence: up to about 100ms (≤50ms until the next check, plus ~17ms to read the track, plus ~33ms to mute). In a live test on 2026-11-05, three interruptions started 24–34ms after the predicted end and were muted within 57–82ms. Song-to-song changes landed 63ms before to 277ms after the prediction, all well inside the watch window.

**The 2-second check** covers everything else: an interruption that starts after a mid-track skip, a missed or wrong prediction, or any missed event. Its worst case is 2 seconds. While Spotify is paused, it runs every 10 seconds.

---

## Restoring the volume

The interruption → music notification triggers a restore right away. The daemon first rereads the current track (one frame) to confirm it really isn't an interruption, then sets the volume (one frame). Roughly 35ms of the new song plays at volume 0. If a notification is ever missed, the 2-second check restores instead and logs that it did.

**Back-to-back interruptions.** Spotify can report a song for about a second between two interruptions, then start the second one without a notification. In the live test this let about a second through before the 2-second check caught it. So for 3 seconds after every restore, the daemon checks the current track every 50ms, the same fast check it uses at track ends. That cuts the gap to about 100ms. It also covers the ~17ms between confirming a song and setting the volume. It can't remove the gap entirely: Spotify doesn't announce the start, so it can only be detected by checking.

---

## Never ending up in a weird state

- **One thread.** Notifications, timers, Spotify launch/quit and SIGTERM/SIGINT are all handled on the main thread, so two state changes can never overlap.
- **Saved volume goes to disk before muting** (`~/Library/Application Support/shall-not-pass/state.json`) and is deleted after a successful restore. If the daemon is killed or crashes mid-interruption, or the Mac restarts, the next start restores your real volume.
- **Spotify quitting mid-interruption.** Spotify remembers volume 0 across launches, so the saved volume is kept and restored once music plays again.
- **You stay in charge.** If you move the slider during an interruption, the daemon stops managing the volume until it ends.
- **Volume rounding.** Spotify rounds volumes (set 85, read back 84). The daemon remembers the volume you chose and ignores ±1 differences, so it doesn't lower the volume one step per interruption.
- **Spotify is never launched by accident.** Any `tell application "Spotify"` would open Spotify, so every call first checks that it's running.
- **No throttling.** `ProcessInfo.beginActivity` and `ProcessType=Interactive` in the LaunchAgent stop macOS from delaying the timers.

---

## Packaging

`shall-not-pass.sh` is the whole program. The Swift source and its Info.plist are embedded at the bottom of the file (`./shall-not-pass.sh --source` prints the Swift). On start, the script builds them with `swiftc` (once per version, cached by hash in `~/Library/Caches/shall-not-pass`), ad-hoc signs the binary, and `exec`s it. Without the Xcode Command Line Tools, the same file runs the original 2-second polling loop.

This means every installer and updater, old or new, only ever copies one file, so none of them can install half an upgrade. (An earlier version shipped a separate binary. A running `update.sh` keeps executing its old contents after `git pull` replaces it, so that first update would have broken.)

The embedded Info.plist supplies `NSAppleEventsUsageDescription`. Without it, macOS can reject Apple Events from the binary without ever showing a permission prompt. Because the binary is ad-hoc signed rather than notarized, macOS may ask for Automation permission again after an update that changes the code.

Set `SHALL_NOT_PASS_DEBUG=1` to log each track-end prediction and how far the actual change landed from it.
