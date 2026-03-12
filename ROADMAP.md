# shall-not-pass — Roadmap

> Last updated: 2026-03-12

---

## Current Status

| Platform | Status |
|----------|--------|
| macOS | ✓ v1 shipped (shell script + launchd) |
| Windows | Planned — see below |
| Android | Planned — see below |
| iOS | Out of scope — see below |

---

## v2: Swift Rewrite (macOS)

The v1 shell script polls every 2 seconds. The right long-term implementation uses Swift with `DistributedNotificationCenter` to subscribe to `com.spotify.client.PlaybackStateChanged` — this fires on every track change and eliminates polling entirely (~0% idle CPU vs. the current ~0.1%).

See [`docs/swift-rewrite-notes.md`](docs/swift-rewrite-notes.md) for contributor context on the v2 implementation.

**What changes in v2:**
- Subscribe to `DistributedNotificationCenter` instead of polling
- Eliminate the 2-second detection latency
- Proper macOS app bundle with notarization path

**What stays the same:**
- AppleScript-based ad detection (`spotify url of current track`)
- Per-app volume control (not system volume)
- No binary modification, no OAuth, no network calls

---

## Windows Plan

Strong ecosystem exists. Recommended approach:

- **Detection:** Windows GSMTC (`Windows.Media.Control` WinRT API) — ads typically have empty album metadata or identifiable title strings
- **Volume control:** WASAPI / Windows Core Audio Session API — per-process volume without affecting other apps
- **Language:** C# with NAudio, or Python via `winsdk`

Reference implementations: DrSaeedHub/spotify-ad-muter (C#/.NET 8, Jan 2026) and Alofte/Spotify-Ad-Muter (Python).

---

## Android Plan

SpotMute's approach (Kotlin, active) is the cleanest no-root option:

1. User enables **Device Broadcast Status** in Spotify Settings → Social
2. Android Notification Listener Service receives track-change events
3. Script detects absence of a new-track notification during playback as an ad signal
4. `AudioManager` mutes the device for the duration

No root needed. No modded APK.

---

## iOS — Out of Scope

Apple's sandboxing model prevents system-wide audio interception, notification listeners for third-party apps, and in-app ad interception without jailbreak. No practical, sustainable, non-jailbreak iOS solution exists. The closest acceptable workaround is using Spotify in Safari with a browser content blocker.

---

## Research Archive

Everything below is the original research document preserved verbatim.

---

## TL;DR

The most practical macOS approach is an **AppleScript-based Spotify volume muter** triggered by Distributed Notifications. It requires no binary patching, no OAuth tokens, and no internet access — just a small script that listens for Spotify track changes and queries the AppleScript dictionary to detect `spotify:ad:` URIs. For iOS, no practical non-jailbreak solution exists.

---

## 1. Existing Solutions

### 1.1 Open Source — Binary Patchers (most aggressive)

These tools modify the Spotify application binary to remove ad serving entirely (audio, banner, video). Most complete, but must be re-applied after every Spotify update.

| Tool | Platform | Stars | Status | Notes |
|------|----------|-------|--------|-------|
| [SpotX](https://github.com/SpotX-Official/SpotX) | Windows | 20.1k | Active | PowerShell patches Spotify binary |
| [SpotX-Bash](https://github.com/SpotX-Official/SpotX-Bash) | macOS/Linux | 5k | Active | Bash script, 235 commits |
| [BlockTheSpot](https://github.com/mrpond/BlockTheSpot) | Windows | Active | Active | Does not work with MS Store version |
| [BlockTheSpot-Mac](https://github.com/Nuzair46/BlockTheSpot-Mac) | macOS | 1.5k | **Archived Dec 2024** | Requires Xcode/codesign; last tested v1.2.32.985 |
| [spotify-adblock](https://github.com/abba23/spotify-adblock) | Linux | Active | Active | Wraps `getaddrinfo` + `cef_urlrequest_create` via library injection |
| [burnt-sushi](https://github.com/OpenByteDev/burnt-sushi) | Windows | Active | Active | DLL injection and function hooking |

### 1.2 Open Source — Ad Muters (detect and mute, don't patch)

These are more relevant to the stated goal: detect ads and mute audio without touching the Spotify binary.

| Tool | Platform | Language | Status | Detection Method |
|------|----------|----------|--------|-----------------|
| [MuteSpotifyAds](https://github.com/simonmeusel/MuteSpotifyAds) | macOS | Swift | **Archived Jan 2020** | AppleScript: checks `spotify url` for `spotify:ad` |
| [gdi3d/mute-spotify-ads-mac-osx](https://github.com/gdi3d/mute-spotify-ads-mac-osx) | macOS | Shell | Unmaintained | `osascript`, lowers system audio |
| [spotify-ad-blocker (s-h-a-d-o-w)](https://github.com/s-h-a-d-o-w/spotify-ad-blocker) | Cross-platform | Node.js | Unmaintained | Mutes only the Spotify process |
| [Alofte/Spotify-Ad-Muter](https://github.com/Alofte/Spotify-Ad-Muter) | Windows | Python | Recent | Ad title detection, controls audio session |
| [DrSaeedHub/spotify-ad-muter](https://github.com/DrSaeedHub/spotify-ad-muter) | Windows | C#/.NET 8 | Jan 2026 | Windows GSMTC API + NAudio per-process volume |
| [SpotMute](https://github.com/samu-developments/SpotMute) | Android | Kotlin | Active | Android Notification Listener; no root needed |
| [EZBlocker](https://github.com/Xeroday/Spotify-Ad-Blocker) | Windows | C# | Unmaintained | Mutes Spotify + Windows hosts file |

### 1.3 DNS / Hosts File Blocklists

| Tool | Approach |
|------|----------|
| [Spotify-AdsList](https://github.com/Isaaker/Spotify-AdsList) | Pi-hole-compatible domain blocklist (243 stars) |
| [x0uid/SpotifyAdBlock](https://github.com/x0uid/SpotifyAdBlock) | Hosts file manipulation, all platforms |
| [Jigsaw88/Spotify-Ad-List](https://github.com/Jigsaw88/Spotify-Ad-List) | Pi-hole blocklist |

**Effectiveness as of 2026:** Increasingly unreliable (~60–80% at best, many report 0%). Spotify now serves many ads from the same CDN domains as music content, making DNS-level blocking either ineffective or likely to break music playback.

### 1.4 MITM Proxy

| Tool | Approach |
|------|----------|
| [AnanthVivekanand/spotify-adblock](https://github.com/AnanthVivekanand/spotify-adblock) | Man-in-the-middle proxy strips ad requests from Spotify desktop |

### 1.5 Browser Extensions (Web Player at open.spotify.com)

- **uBlock Origin** — most effective; blocks audio and banner ads on the web player
- **Blockify** (Chrome) — dedicated Spotify extension with dual-layer block + mute fallback
- **Spotless** (Chrome) — Spotify-specific ad muter
- **AdGuard Browser Extension** — cross-browser

### 1.6 Commercial Solutions

- **AdGuard** (paid): Desktop app (macOS/Windows) + Android VPN-mode (no root). Most stable cross-platform option that doesn't require Spotify client modification. Not Spotify-specific — general ad blocking.
- **Sound Control** (paid macOS): Per-app volume control with an AppleScript dictionary. Could be scripted to automate Spotify muting, but adds a paid dependency for something achievable natively.
- No dedicated paid Spotify ad-muter products exist that are marketed as such.

---

## 2. Technical Approaches

### 2.1 Spotify Web API — Currently Playing Endpoint (Recommended for reliability, with caveats)

`GET /v1/me/player/currently-playing` returns a `currently_playing_type` field: `"track"`, `"episode"`, `"ad"`, or `"unknown"`.

This is the **cleanest, most explicit ad-detection signal available** — Spotify itself is telling you it's playing an ad.

**Requirements and caveats:**
- OAuth2 with `user-read-currently-playing` scope
- As of **February 2026**, Spotify requires the developer to have a **Premium account** to register a developer app, and development-mode apps are capped at **5 users**
- Apps needing more users must apply for Extended Quota Mode — not guaranteed to be approved for an ad-muting use case
- **Practical implication:** Works fine for a personal tool (you authenticate your own account), but cannot be easily distributed to arbitrary free-tier users without each user registering their own Spotify app
- Poll every 3–5 seconds; respond to `Retry-After` on 429s

### 2.2 AppleScript via Spotify's Scripting Dictionary (Best macOS-native approach)

The Spotify macOS desktop app exposes an AppleScript dictionary. Key properties:

```applescript
tell application "Spotify"
    get spotify url of current track   -- "spotify:ad:XXXX" during ads
    get sound volume                    -- integer 0–100
    set sound volume to 0               -- mutes only Spotify (not system audio)
    get player state                    -- playing, paused, stopped
end tell
```

**Key insight:** `spotify url of current track` returns a URI starting with `spotify:ad:` during advertisements. This has been the detection mechanism used by macOS muter tools since at least 2018.

**Triggering efficiently (no polling needed):** The Spotify macOS app broadcasts `com.spotify.client.PlaybackStateChanged` via macOS Distributed Notifications on every track change. A Swift/Objective-C app can subscribe to `DistributedNotificationCenter` and only query AppleScript when a track change actually occurs — essentially zero idle CPU.

**Caveat:** Spotify has periodically broken AppleScript support in updates. Community threads confirm this happens intermittently. The dictionary still appears functional as of early 2026 based on available reports, but there is no guarantee of ongoing support.

### 2.3 System Audio Volume Control on macOS

Two distinct levels:

**Option A: Per-app volume (preferred)**
```applescript
-- Only affects Spotify; other apps unaffected
tell application "Spotify" to set sound volume to 0
tell application "Spotify" to set sound volume to [saved_volume]
```

**Option B: System-wide volume (simpler, but affects everything)**
```bash
# Save current volume
SAVED=$(osascript -e "output volume of (get volume settings)")
# Mute
osascript -e "set volume output volume 0"
# Restore
osascript -e "set volume output volume $SAVED"
```

Option A is strongly preferred — it doesn't interrupt other audio (music from a browser tab, system sounds, video calls, etc.).

**Option C: CoreAudio per-process programmatic control** — possible via C/Swift using `AudioHardware.h` but complex. Background Music implements this via a virtual audio driver.

### 2.4 Windows-Specific Detection

- **GSMTC (Global System Media Transport Controls):** Accessed via `Windows.Media.Control` WinRT API (C# or Python via `winsdk`). Detects ad-playing state — ads typically have empty album metadata or identifiable title strings.
- **Per-process volume:** Windows WASAPI / CoreAudio Session APIs control per-app volume without affecting other apps. NAudio (C#) wraps this cleanly.
- **Window title monitoring (legacy):** Older tools (EZBlocker) detected ads when Spotify's window title became "Advertisement" or blank. Less reliable than GSMTC.

### 2.5 Android — Notification Listener (No Root)

The cleanest Android approach, as used by SpotMute:
1. Enable **"Device Broadcast Status"** in Spotify Settings → Social
2. Implement an Android Notification Listener Service
3. Spotify sends track-change notifications; absence of a new-track notification during playback indicates an ad
4. Mute device audio for the duration

Requires zero permissions beyond notification listener access. No root. No modded APK.

### 2.6 Spotify Local API — DEPRECATED

The old Spotify desktop client ran a local HTTP server at `127.0.0.1:4370–4380` that served current track info. Libraries like `spotilocal` and `spotify-web-helper` used this. **Removed in current Spotify desktop versions.** Do not build on this.

### 2.7 Binary Patching

SpotX-Bash and BlockTheSpot-Mac directly modify Spotify's app bundle. Complete ad removal (audio, video, banners). Downsides:
- Must be re-applied after every Spotify update
- BlockTheSpot-Mac requires Xcode (significant macOS barrier)
- SpotX-Bash is actively maintained (5k stars) and is the leading macOS/Linux patcher
- Highest ToS violation risk

---

## 3. Platform Feasibility

### macOS Desktop — High Feasibility

**Recommended implementation:**
1. Subscribe to `com.spotify.client.PlaybackStateChanged` via `DistributedNotificationCenter`
2. On notification: query `spotify url of current track` via AppleScript
3. If URL starts with `spotify:ad:`: call `tell application "Spotify" to set sound volume to 0`; save current volume first
4. When next non-ad track notification arrives: restore saved volume

This approach:
- ~0% CPU when idle
- No network calls, no OAuth, no dependencies
- Only mutes Spotify — doesn't affect other apps
- ~50–100 lines of code in Swift, Python, or shell script
- No binary modification

**Risk:** AppleScript dictionary breakage in future Spotify updates (mitigated by open source community maintenance).

### Windows Desktop — High Feasibility

Strong ecosystem. GSMTC + WASAPI per-process volume is the cleanest modern approach. SpotX/BlockTheSpot are the dominant tools if you want full ad removal.

### Android — Moderate Feasibility (No Root)

SpotMute's notification listener approach works without root, but requires the user to manually enable "Device Broadcast Status" in Spotify settings. AdGuard's local VPN approach is more transparent but is a general ad blocker, not Spotify-specific.

### iOS — Very Low Feasibility (Without Jailbreak)

Apple's sandboxing model prevents:
- System-wide audio interception
- Notification listeners for third-party apps
- In-app ad interception

Options that technically work but are impractical:
- **EeveeSpotify Reborn**: Sideloaded .ipa via AltStore; requires Xcode + weekly re-signing. High maintenance.
- **DNS/NextDNS/AdGuard DNS**: Inconsistent; Spotify serves ads from music CDNs
- **Modded apps from third-party stores**: Violate ToS, risk account ban, security risk

**Verdict:** No practical, sustainable, non-jailbreak iOS solution exists for in-app ad suppression. The closest acceptable workaround is using Spotify in Safari and blocking ads via a browser content blocker.

---

## 4. Legal / Terms of Service

**Spotify's User Guidelines explicitly prohibit:**
> "circumventing or blocking advertisements or creating or distributing tools designed to block advertisements"

**Key points:**
- Violations can result in account suspension or termination without warning
- Spotify announced enforcement against ad-block users circa 2019; actual bans have been reported but are not universal
- Risk appears higher for binary-patching tools (SpotX, BlockTheSpot) than for muting-only tools — patching the app is harder to ignore than a volume change
- A muting tool where the ad still plays and Spotify technically still gets paid is a stronger legal position than a blocking tool (though Spotify's ToS language covers both)
- **Distributing** a tool explicitly designed to mute/block Spotify ads is explicitly prohibited
- Building and using a personal tool for yourself is in the most defensible position, though still technically against ToS

**Developer ToS:** Using the Spotify Web API to detect and mute ads could also violate Developer Terms. However, polling currently-playing for personal use is a gray area.

**Practical reality:** Thousands of users actively use SpotX, BlockTheSpot-Mac, and similar tools. Mass enforcement has not occurred. Risk is real but enforcement is selective.

---

## 5. Open Source vs. Paid Product

### Open Source (strongly recommended)

**Reasons to go open source:**
1. **Legal exposure**: "Creating or distributing tools designed to block advertisements" violates ToS regardless of pricing. Charging money dramatically increases legal and business risk.
2. **Maintenance model**: Spotify periodically breaks AppleScript and API integrations. Open source enables community patching (SpotX-Bash demonstrates this: 235+ commits).
3. **Competitive landscape**: SpotX-Bash (5k stars), BackgroundMusic (18.7k stars), and free web extensions dominate. A paid tool competes against free, established alternatives.
4. **Personal-use carve-out**: Open source for personal use is the most defensible legal position.
5. **Community trust**: A paid tool for something ToS-violating faces skepticism. Open source gets adoption from the technical community who can audit it.

### Paid Product (not recommended, but if pursued)

The only defensible paid-product angle: position it as a **general macOS per-app audio manager** (like Sound Control or Background Music) with Spotify muting as an incidental feature, never marketed as an "ad blocker/muter." This avoids the explicit ToS violation of "distributing tools designed to block advertisements."

---

## 6. Recommended Implementation for This Project

Given the goal (macOS desktop, primary focus; mobile secondary), here is the recommended technical approach:

### macOS — Shell Script / Python Daemon

**Detection:** AppleScript `spotify url` check, triggered by `com.spotify.client.PlaybackStateChanged` Distributed Notification.

**Volume control:** `tell application "Spotify" to set sound volume to [0 | saved]` (per-app, not system-wide).

**Rough implementation:**

```bash
#!/bin/bash
# Poll approach (simple, no notification subscription needed for a PoC)
SAVED_VOLUME=$(osascript -e 'tell application "Spotify" to get sound volume')
AD_PLAYING=false

while true; do
    CURRENT_URL=$(osascript -e 'tell application "Spotify" to get spotify url of current track' 2>/dev/null)
    if [[ "$CURRENT_URL" == spotify:ad:* ]]; then
        if [ "$AD_PLAYING" = false ]; then
            SAVED_VOLUME=$(osascript -e 'tell application "Spotify" to get sound volume')
            osascript -e 'tell application "Spotify" to set sound volume to 0'
            AD_PLAYING=true
        fi
    else
        if [ "$AD_PLAYING" = true ]; then
            osascript -e "tell application \"Spotify\" to set sound volume to $SAVED_VOLUME"
            AD_PLAYING=false
        fi
    fi
    sleep 2
done
```

A production version would use Swift + `DistributedNotificationCenter` to avoid polling entirely.

**Fallback:** If AppleScript `spotify url` breaks in a future Spotify update, fall back to the Spotify Web API `currently_playing_type: "ad"` field (requires OAuth token but is explicit and reliable).

### Android

Use SpotMute's approach: Android Notification Listener Service + "Device Broadcast Status" in Spotify settings. No root needed. Could be extended with a per-app volume mute (AudioManager) rather than device-wide mute.

### iOS

No practical implementation. Document this clearly as out of scope.

---

## 7. Key GitHub Projects Reference

| Project | Platform | Approach | Stars | Status |
|---------|----------|----------|-------|--------|
| [SpotX](https://github.com/SpotX-Official/SpotX) | Windows | Binary patch | 20.1k | Active |
| [SpotX-Bash](https://github.com/SpotX-Official/SpotX-Bash) | macOS/Linux | Binary patch | 5k | Active |
| [BackgroundMusic](https://github.com/kyleneideck/BackgroundMusic) | macOS | Per-app audio driver | 18.7k | Alpha |
| [BlockTheSpot](https://github.com/mrpond/BlockTheSpot) | Windows | Binary patch | Active | Active |
| [BlockTheSpot-Mac](https://github.com/Nuzair46/BlockTheSpot-Mac) | macOS | Binary patch | 1.5k | Archived Dec 2024 |
| [spotify-adblock](https://github.com/abba23/spotify-adblock) | Linux | Library injection | Active | Active |
| [MuteSpotifyAds](https://github.com/simonmeusel/MuteSpotifyAds) | macOS | AppleScript mute | Low | Archived 2020 |
| [SpotMute](https://github.com/samu-developments/SpotMute) | Android | Notification listener | Active | Active |
| [EZBlocker](https://github.com/Xeroday/Spotify-Ad-Blocker) | Windows | Mute + hosts | Moderate | Unmaintained |
| [Spotify-AdsList](https://github.com/Isaaker/Spotify-AdsList) | Network | Pi-hole blocklist | 243 | Active |
| [AnanthVivekanand/spotify-adblock](https://github.com/AnanthVivekanand/spotify-adblock) | Desktop | MITM proxy | Low | Available |
