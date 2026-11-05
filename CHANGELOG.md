# Changelog

## v2.0.0

A rewrite of the daemon in Swift. It is still one file, `shall-not-pass.sh`, and every installer and updater picks it up.

- **Mutes within about a tenth of a second** when an interruption starts at the end of a track. Supported apps don't announce when an interruption starts, so the daemon predicts when each track will end and checks every 50ms around that moment. A check every 2 seconds catches anything else.
- **Restores the volume as soon as your content comes back**, using the app's own playback notifications.
- **Back-to-back interruptions** are caught by fast checks for 3 seconds after each restore.
- **Can't get stuck at zero.** The volume is saved to disk before it's lowered, so a crash, a restart, or the app quitting can't lose it.
- **No drift.** The app rounds volumes; the daemon no longer lowers your volume one step per interruption.
- **You stay in charge.** Move the slider during an interruption and it backs off until the interruption ends.
- **Falls back to the v1 script** if the Xcode Command Line Tools aren't installed.
- **Updates without a clone:** re-run the install command, or `~/.local/share/shall-not-pass/update.sh`, which follows whichever install method the machine used (recorded in `install-info`).
- CI, a bug report template, [How it works](docs/how-it-works.md), and [Troubleshooting](docs/troubleshooting.md).

## v1

A shell script that checks every 2 seconds and lowers the volume during interruptions. Installs as a LaunchAgent, with a one-line curl install.
