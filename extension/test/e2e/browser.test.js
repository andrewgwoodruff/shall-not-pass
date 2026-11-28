// Loads the real extension into Chromium, serves the fixture pages at the
// sites' real addresses, and checks that the tab is muted and unmuted.
import { after, before, test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const extension = fileURLToPath(new URL("../..", import.meta.url));
const fixture = (name) => readFileSync(new URL(`../fixtures/${name}.html`, import.meta.url), "utf8");

let context, worker;

before(async () => {
  context = await chromium.launchPersistentContext("", {
    // BROWSER=msedge (or chrome, etc.) runs these in an installed browser instead.
    channel: process.env.BROWSER ?? "chromium",
    args: [`--disable-extensions-except=${extension}`, `--load-extension=${extension}`],
  });
  worker = context.serviceWorkers()[0] ?? (await context.waitForEvent("serviceworker"));
});

after(() => context?.close());

// The extension can't see tab addresses (it doesn't ask for that permission),
// so the new tab is found by its id: the one that wasn't there before.
const tabIds = () => worker.evaluate(async () => (await chrome.tabs.query({})).map((t) => t.id));

async function open(url, html) {
  await context.route(url, (route) => route.fulfill({ contentType: "text/html", body: html }));
  const before = await tabIds();
  const page = await context.newPage();
  await page.goto(url);
  const tabId = (await tabIds()).find((id) => !before.includes(id));
  const muted = () => worker.evaluate(async (id) => (await chrome.tabs.get(id)).mutedInfo.muted, tabId);
  return { page, tabId, muted };
}

async function until(check, expected) {
  for (let i = 0; i < 50; i++) {
    if ((await check()) === expected) return;
    await new Promise((r) => setTimeout(r, 100));
  }
  assert.fail(`still ${!expected} after 5s`);
}

// Swap the page's contents for another fixture, the way the site's own scripts would.
const become = (page, html) => page.evaluate((html) => (document.body.innerHTML = html), html);

for (const site of ["youtube", "spotify"]) {
  const url = site === "youtube" ? "https://www.youtube.com/watch?v=test" : "https://open.spotify.com/";

  test(`${site}: mutes during an interruption and unmutes after`, async () => {
    const { page, muted } = await open(url, fixture(`${site}-playing`));
    await until(muted, false);
    await become(page, fixture(`${site}-interrupted`));
    await until(muted, true);
    await become(page, fixture(`${site}-playing`));
    await until(muted, false);
    await page.close();
  });
}

// Spotify starts the next track a moment before its page shows what it is.
// These play the part of Spotify's player: start a (silent) track, then drop
// it the way the player does when it moves on.
const nextSong = fixture("spotify-playing").replaceAll("Declaration of Indo-Pendence", "Married Life").replace("/album/ID", "/album/ID2");
// play() never settles without a source, so it isn't awaited.
const startPlayer = (page) => page.evaluate(() => void (window.player = document.createElement("video")).play().catch(() => {}));
const changeTrack = (page) => page.evaluate(() => window.player.dispatchEvent(new Event("emptied")));

async function spotifyPlaying(name) {
  const tab = await open(`https://open.spotify.com/${name}`, fixture("spotify-playing"));
  await until(tab.muted, false);
  await startPlayer(tab.page);
  return tab;
}

test("spotify: goes quiet the instant a track changes, before the page shows what's next", async () => {
  const { page, muted } = await spotifyPlaying("next-song");
  await changeTrack(page);
  await until(muted, true); // the page still shows the old song
  await become(page, nextSong);
  await until(muted, false);
  await page.close();
});

test("spotify: a track change into an interruption stays quiet throughout", async () => {
  const { page, muted } = await spotifyPlaying("next-interruption");
  await changeTrack(page);
  await until(muted, true);
  await become(page, fixture("spotify-interrupted"));
  await new Promise((r) => setTimeout(r, 3500)); // past the longest hold
  assert.equal(await muted(), true);
  await changeTrack(page);
  await become(page, fixture("spotify-playing"));
  await until(muted, false);
  await page.close();
});

test("spotify: the same song again gets its sound back within a few seconds", async () => {
  const { page, muted } = await spotifyPlaying("same-song");
  await changeTrack(page);
  await until(muted, true);
  await until(muted, false); // the page never changes; the hold runs out
  await page.close();
});

test("a page that opens mid-interruption is muted right away", async () => {
  const { page, muted } = await open("https://www.youtube.com/watch?v=already", fixture("youtube-interrupted"));
  await until(muted, true);
  await page.close();
});

test("you stay in charge: unmuting during an interruption sticks", async () => {
  const { page, tabId, muted } = await open("https://www.youtube.com/watch?v=user", fixture("youtube-playing"));
  await become(page, fixture("youtube-interrupted"));
  await until(muted, true);
  // Unmute it, as you would with the tab's speaker icon.
  await worker.evaluate((id) => chrome.tabs.update(id, { muted: false }), tabId);
  await new Promise((r) => setTimeout(r, 1500)); // past the 1s backstop check
  assert.equal(await muted(), false);
  await page.close();
});

test("other sites are never touched", async () => {
  const { page, muted } = await open("https://example.com/", fixture("youtube-interrupted"));
  await new Promise((r) => setTimeout(r, 1500));
  assert.equal(await muted(), false);
  await page.close();
});
