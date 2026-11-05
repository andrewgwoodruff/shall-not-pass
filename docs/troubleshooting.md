# Troubleshooting

Try these in order.

**1. Check the log:** is the daemon running, and what is it seeing?
```bash
tail -f ~/Library/Logs/shall-not-pass.log
```

**2. Check that the daemon is loaded** (the first column should show a PID)
```bash
launchctl list | grep shall-not-pass
```

**3. Check Automation permission**
System Settings -> Privacy & Security -> Automation -> shall-not-pass (or your terminal app, for the shell-script version) must have Spotify checked. Because each build is ad-hoc signed, macOS may ask again after an update.

**4. Restart the daemon**
```bash
launchctl unload ~/Library/LaunchAgents/com.shall-not-pass.plist
launchctl load -w ~/Library/LaunchAgents/com.shall-not-pass.plist
```

**5. Update.** Spotify has occasionally broken AppleScript support in app updates, and fixes ship here.
```bash
~/.local/share/shall-not-pass/update.sh
```

**6. Uninstall and reinstall.** The clean-slate fix, safe to run anytime.
```bash
~/.local/share/shall-not-pass/uninstall.sh
curl -fsSL https://raw.githubusercontent.com/andrewgwoodruff/shall-not-pass/main/install.sh | bash
```

**7. Still broken?** [Open an issue](https://github.com/andrewgwoodruff/shall-not-pass/issues) and include the output of `tail -50 ~/Library/Logs/shall-not-pass.log`.

For more detail in the log, run it in the foreground with `SHALL_NOT_PASS_DEBUG=1 bash ~/.local/share/shall-not-pass/shall-not-pass.sh` (stop the LaunchAgent first, step 4).

---

## Updating

`~/.local/share/shall-not-pass/update.sh` works for either install method. It reads `install-info` to see how the machine was installed and does the matching update:

- **Quick install:** re-runs the install command. No clone needed:
  ```bash
  curl -fsSL https://raw.githubusercontent.com/andrewgwoodruff/shall-not-pass/main/install.sh | bash
  ```
- **Manual install:** from the cloned repo, `./update.sh` (pulls and reinstalls).

Installs from before `update.sh` existed don't have it until their next update. The quick-install command updates any machine correctly.

### Which install method did this machine use?

```bash
cat ~/.local/share/shall-not-pass/install-info
```

It shows `method=quick` or `method=manual` (plus the clone's path and commit). If the file is missing, the machine was installed before this was recorded.

---

## Where things live

| What | Where |
|---|---|
| The program | `~/.local/share/shall-not-pass/shall-not-pass.sh` (the Swift source is embedded at the bottom) |
| Compiled daemon | `~/Library/Caches/shall-not-pass/` |
| LaunchAgent | `~/Library/LaunchAgents/com.shall-not-pass.plist` |
| Saved volume (only during an interruption) | `~/Library/Application Support/shall-not-pass/state.json` |
| Log | `~/Library/Logs/shall-not-pass.log` |

`uninstall.sh` removes all of them except the log.
