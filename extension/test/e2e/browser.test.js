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
    channel: "chromium",
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
