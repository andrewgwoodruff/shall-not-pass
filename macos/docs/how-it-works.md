# How it works

`shall-not-pass` is a small background program (a macOS LaunchAgent). It talks to the Spotify desktop app through the scripting interface Spotify provides for macOS, and the only thing it ever changes is Spotify's own volume slider.

## Turning the volume down

Spotify announces when playback starts, pauses, or changes songs, but not when an interruption starts. Interruptions only start where a track ends, though, so `shall-not-pass`:

1. **Predicts when the current track will end**, from its length and how far into it you are.
2. **Checks what's playing every 50ms** around that moment.
3. **Saves your volume and sets it to 0** as soon as an interruption appears.

In testing, that takes under a tenth of a second. A slower check every 2 seconds catches anything the prediction misses, such as an interruption after you skip mid-track.

## Turning it back up

Spotify does announce when your content comes back. `shall-not-pass` double-checks what's playing, then restores the exact volume you had. For a few seconds afterwards it keeps checking every 50ms, in case another interruption follows right behind.

## Staying out of your way

- **You stay in charge.** If you move the slider during an interruption, it leaves the volume alone until the interruption ends.
- **It can't get stuck at zero.** Your volume is saved to disk before it's lowered, so a crash, a restart, or Spotify quitting can't lose it.
- **It never opens Spotify for you.** It only talks to Spotify while Spotify is already running.
- **It does one thing at a time.** Every event is handled in order on a single thread, so two changes can never collide.

## One file

[`shall-not-pass.sh`](../shall-not-pass.sh) is the whole program; the Swift source is embedded at the bottom. On first run (and after each update), it compiles the Swift once with the Xcode Command Line Tools and caches the result. Without those tools, it falls back to the 2-second check alone.

To see each prediction and how close it was, run with `SHALL_NOT_PASS_DEBUG=1`.
