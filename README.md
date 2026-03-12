# shall-not-pass

*Stands watch so you don't have to.*
*For a life with fewer interruptions.*

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A macOS daemon that silences audio interruptions in Spotify without modifying the Spotify binary, touching system volume, or requiring any dependencies.

---

## How it works

Spotify's macOS app exposes an AppleScript dictionary. Every two seconds, `shall-not-pass` checks the current track's URI — during ads, Spotify returns a URI starting with `spotify:ad:`. When an ad is detected, the script sets Spotify's own volume to zero (not your system volume) and restores it the moment the ad ends. Your other apps are never affected.

---

## Requirements

- macOS 12 or later
- Spotify desktop app
- No other dependencies — uses only `bash`, `osascript`, and `launchd`, which ship with every Mac

---

## Install

**Quick install** — paste this in Terminal and it handles everything:

```bash
curl -fsSL https://raw.githubusercontent.com/andrewwoodruff/shall-not-pass/main/install.sh | bash
```

**Manual install** — if you'd prefer to read the code before running it:

```bash
git clone https://github.com/andrewwoodruff/shall-not-pass.git
cd shall-not-pass
# inspect shall-not-pass.sh and install.sh, then:
./install.sh
```

Both options copy the script to `~/.local/share/shall-not-pass/` and register it as a LaunchAgent that starts automatically at login.

> **Note:** macOS will likely prompt for Automation permission on first run. Open **System Settings → Privacy & Security → Automation** and allow your terminal to control Spotify.

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
curl -fsSL https://raw.githubusercontent.com/andrewwoodruff/shall-not-pass/main/install.sh | bash
```

**Manual install users** — from the cloned repo directory:

```bash
./update.sh
```

Either way, this is also the first thing to try if Spotify ever breaks AppleScript support — a fix will ship and re-running this will apply it.

---

## Uninstall

```bash
~/.local/share/shall-not-pass/uninstall.sh
```

Stops the daemon and removes all installed files. No data is lost.

---

## Known limitations

- **~2 second detection latency** — the poll interval means the first two seconds of an ad may be audible before muting kicks in
- **AppleScript breakage** — Spotify has occasionally broken AppleScript support in updates; if this happens, run `./update.sh` first, then check the troubleshooting section below
- **Automation permission prompt** — macOS requires explicit permission for terminal apps to control Spotify via AppleScript

---

## Troubleshooting

Try these in order:

**1. Check the log** — is the daemon running and what is it seeing?
```bash
tail -f ~/Library/Logs/shall-not-pass.log
```

**2. Check if the daemon is loaded** — should show a PID in the first column
```bash
launchctl list | grep shall-not-pass
```

**3. Check Automation permission**
System Settings → Privacy & Security → Automation → your terminal app must have Spotify checked.

**4. Restart the daemon**
```bash
launchctl unload ~/Library/LaunchAgents/com.shall-not-pass.plist
launchctl load -w ~/Library/LaunchAgents/com.shall-not-pass.plist
```

**5. Update first** — many issues are fixed in newer versions
```bash
# Quick install users:
curl -fsSL https://raw.githubusercontent.com/andrewwoodruff/shall-not-pass/main/install.sh | bash
# Manual install users (from repo dir):
./update.sh
```

**6. Nuke and reinstall** — the clean-slate fix; safe to run anytime
```bash
~/.local/share/shall-not-pass/uninstall.sh
curl -fsSL https://raw.githubusercontent.com/andrewwoodruff/shall-not-pass/main/install.sh | bash
```

---

## Platform support

| Platform | Status |
|----------|--------|
| macOS | ✓ Supported (v1) |
| Windows | Planned |
| Android | Planned |
| iOS | Out of scope (see ROADMAP.md) |

---

## Legal

Personal-use tool. Use at your own discretion. Not affiliated with or endorsed by Spotify.
See [ROADMAP.md](ROADMAP.md) for a full discussion of approaches and tradeoffs.
