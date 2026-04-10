# shall-not-pass

*Stands watch so you don't have to.*
*For a life with fewer interruptions.*

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A macOS daemon that acts as an automatic volume control for your listening session. It steps in when you'd step in yourself, and steps back out when you wouldn't.

---

## What it does

You already have the right to turn down your volume whenever you want. `shall-not-pass` just does it for you automatically, so you don't have to be sitting at your desk with your hand on the knob.

When it detects an audio interruption, it quietly lowers the app's volume. When your content resumes, it restores it, exactly as it was. Your system volume is never touched. No other apps are affected.

**Current version:** Spotify on macOS. Support for other platforms and apps is [on the roadmap](ROADMAP.md).

---

## Requirements

- macOS 12 or later
- Spotify desktop app
- No other dependencies. Uses only `bash`, `osascript`, and `launchd`, which ship with every Mac.

---

## Install

**Quick install** — paste this in Terminal and it handles everything:

```bash
curl -fsSL https://raw.githubusercontent.com/andrewgwoodruff/shall-not-pass/main/install.sh | bash
```

**Manual install** — if you'd prefer to read the code before running it:

```bash
git clone https://github.com/andrewgwoodruff/shall-not-pass.git
cd shall-not-pass
# inspect shall-not-pass.sh and install.sh, then:
./install.sh
```

Both options copy the script to `~/.local/share/shall-not-pass/` and register it as a LaunchAgent that starts automatically at login.

> **Required:** The installer will request Automation permission from macOS. This is not optional — without it, the daemon cannot control Spotify's volume. A dialog will appear during install; click OK. If Spotify is not open at install time, the prompt will appear the first time you open Spotify. If you ever dismiss it by accident: **System Settings -> Privacy & Security -> Automation** and enable your terminal app to control Spotify.

### Try before installing

If you used the manual install, you can run it in the foreground first to see what it does:

```bash
bash shall-not-pass.sh
```

Press `Ctrl-C` to stop. It will restore Spotify's volume before exiting.

---

## Updating

**Quick install users** — re-run the same install command:

```bash
curl -fsSL https://raw.githubusercontent.com/andrewgwoodruff/shall-not-pass/main/install.sh | bash
```

**Manual install users** — from the cloned repo directory:

```bash
./update.sh
```

Either way, this is also the first thing to try if a Spotify app update ever causes issues. A fix will ship and re-running this will apply it.

---

## Uninstall

```bash
~/.local/share/shall-not-pass/uninstall.sh
```

Stops the daemon and removes all installed files. No data is lost.

---

## Known limitations

- **~2 second detection latency:** the poll interval means the first two seconds of an interruption may be audible before muting kicks in
- **AppleScript breakage:** Spotify has occasionally broken AppleScript support in app updates. Run `./update.sh` if you notice it stop working.
- **Automation permission required:** macOS requires explicit permission for your terminal to control Spotify. The installer requests this automatically. If it was denied or revoked, the daemon will log a clear error with instructions.

---

## Troubleshooting

Try these in order:

**1. Check the log:** is the daemon running and what is it seeing?
```bash
tail -f ~/Library/Logs/shall-not-pass.log
```

**2. Check if the daemon is loaded** (should show a PID in the first column)
```bash
launchctl list | grep shall-not-pass
```

**3. Check Automation permission**
System Settings -> Privacy & Security -> Automation -> your terminal app must have Spotify checked.

**4. Restart the daemon**
```bash
launchctl unload ~/Library/LaunchAgents/com.shall-not-pass.plist
launchctl load -w ~/Library/LaunchAgents/com.shall-not-pass.plist
```

**5. Update first:** many issues are fixed in newer versions
```bash
# Quick install users:
curl -fsSL https://raw.githubusercontent.com/andrewgwoodruff/shall-not-pass/main/install.sh | bash
# Manual install users (from repo dir):
./update.sh
```

**6. Nuke and reinstall:** the clean-slate fix, safe to run anytime
```bash
~/.local/share/shall-not-pass/uninstall.sh
curl -fsSL https://raw.githubusercontent.com/andrewgwoodruff/shall-not-pass/main/install.sh | bash
```

**7. Still broken?** [Open an issue](https://github.com/andrewgwoodruff/shall-not-pass/issues) and include the output of `tail -50 ~/Library/Logs/shall-not-pass.log`.

---

## Platform support

| Platform | Status |
|----------|--------|
| macOS (Spotify) | Supported (v1) |
| Windows | Planned |
| Android | Planned |
| iOS | Out of scope (see ROADMAP.md) |

---

## Legal

This tool automates a volume adjustment you are fully entitled to make yourself. It does not modify any application, bypass any technical protection, or access any system you are not authorized to use.

Personal-use tool. Use at your own discretion. Not affiliated with or endorsed by Spotify.
