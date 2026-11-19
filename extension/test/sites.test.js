import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { parseHTML } from "linkedom";

async function load(site) {
  await import(`../src/sites/${site}.js?${site}`);
  return globalThis.shallNotPassSite;
}

const page = (html) => parseHTML(`<!doctype html><html><body>${html}</body></html>`).document;
const fixture = (name) => page(readFileSync(new URL(`fixtures/${name}.html`, import.meta.url), "utf8"));

test("YouTube: playing is not an interruption", async () => {
  assert.equal((await load("youtube")).isInterrupted(fixture("youtube-playing")), false);
});

test("YouTube: interrupted", async () => {
  assert.equal((await load("youtube")).isInterrupted(fixture("youtube-interrupted")), true);
});

test("YouTube: pages without a player", async () => {
  assert.equal((await load("youtube")).isInterrupted(page("<div id=contents></div>")), false);
});

test("Spotify: playing is not an interruption", async () => {
  assert.equal((await load("spotify")).isInterrupted(fixture("spotify-playing")), false);
});

test("Spotify: interrupted", async () => {
  assert.equal((await load("spotify")).isInterrupted(fixture("spotify-interrupted")), true);
});

test("Spotify: nothing playing, or the bar still loading", async () => {
  const spotify = await load("spotify");
  assert.equal(spotify.isInterrupted(page("<main></main>")), false);
  assert.equal(spotify.isInterrupted(page('<div data-testid="now-playing-widget-v2"></div>')), false);
});

test("Spotify: podcasts and absolute links count as content", async () => {
  const spotify = await load("spotify");
  const bar = (links) =>
    page(`<div data-testid="now-playing-widget-v2">${links.map((h) => `<a href="${h}">x</a>`).join("")}</div>`);
  assert.equal(spotify.isInterrupted(bar(["/episode/ID", "/show/ID"])), false);
  assert.equal(spotify.isInterrupted(bar(["https://open.spotify.com/album/ID"])), false);
  assert.equal(spotify.isInterrupted(bar(["https://open.spotify.com.evil.example/album/ID"])), true);
});
