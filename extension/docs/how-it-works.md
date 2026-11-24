# How the browser extension works

The extension runs only on `www.youtube.com` and `open.spotify.com`. When an interruption starts in one of those tabs, it mutes that tab. When your content comes back, it unmutes it. Other tabs, other sites, and your computer's volume are never touched.

## Noticing an interruption

Each site gets a small detector that reads what the page already shows:

- **YouTube:** the video player switches into a distinct mode for as long as an interruption plays, including several in a row.
- **Spotify:** the now-playing bar links to the album and artist (or show and episode) of what's playing. During an interruption, it links to the sponsor instead. Checking where the links go, not what the text says, works in every language.

The page tells the extension the moment it changes, so there's nothing to predict and no timer to wait on. A check once a second backs that up.

Spotify starts the next track a fraction of a second before the bar shows what it is. So on Spotify, the tab goes quiet the instant one track ends, before the next one makes a sound, and stays quiet until the bar shows what's playing. Songs get their sound back right away; interruptions are never heard. If the bar doesn't change within 3 seconds (the same song again), the sound comes back anyway.

## Muting the tab

The extension uses Chrome's own tab mute, the same as clicking the speaker icon on the tab. It doesn't block, skip, or change anything on the page; everything plays in full, just muted.

- **You stay in charge.** Unmute the tab during an interruption and it stays unmuted. A tab you muted yourself is never unmuted.
- **It can't leave a tab silent.** Chrome remembers which extension muted a tab, and that's the only record the extension keeps. If a page reloads or navigates away mid-interruption, the new page reports in and the sound comes back. After an update, the extension unmutes any tab it had muted.

## Code

- [`src/sites/`](../src/sites): one detector per site, plus [`spotify-player.js`](../src/sites/spotify-player.js), which notices Spotify's track changes
- [`src/content.js`](../src/content.js): watches the page and reports changes
- [`src/mute.js`](../src/mute.js): mutes and unmutes tabs

Tests run the detectors against saved snapshots of each page, and load the real extension into Chromium to check that tabs mute and unmute: `npm test` and `npm run test:browser`.
