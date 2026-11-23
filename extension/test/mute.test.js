import { test } from "node:test";
import assert from "node:assert/strict";
import "../src/mute.js";

const ID = "our-extension";

// A stand-in for chrome.tabs that records mute changes the way Chrome does.
function fakeTabs(initial = {}) {
  const tabs = new Map(Object.entries(initial).map(([id, mutedInfo]) => [Number(id), { id: Number(id), mutedInfo }]));
  return {
    tabs,
    async get(id) {
      if (!tabs.has(id)) throw new Error("No tab with id");
      await Promise.resolve();
      return structuredClone(tabs.get(id));
    },
    async update(id, { muted }) {
      await Promise.resolve();
      tabs.get(id).mutedInfo = muted ? { muted, reason: "extension", extensionId: ID } : { muted };
    },
    async query({ muted }) {
      return [...tabs.values()].filter((t) => t.mutedInfo.muted === muted).map((t) => structuredClone(t));
    },
    userSets(id, muted) {
      tabs.get(id).mutedInfo = { muted, reason: "user" };
    },
    muted: (id) => tabs.get(id).mutedInfo.muted,
  };
}

test("mutes during an interruption and unmutes after", async () => {
  const tabs = fakeTabs({ 1: { muted: false } });
  const muter = createMuter(tabs, ID);
  await muter.report(1, true);
  assert.equal(tabs.muted(1), true);
  await muter.report(1, false);
  assert.equal(tabs.muted(1), false);
});

test("never unmutes a tab you muted yourself", async () => {
  const tabs = fakeTabs({ 1: { muted: true, reason: "user" } });
  const muter = createMuter(tabs, ID);
  await muter.report(1, true);
  await muter.report(1, false);
  assert.equal(tabs.muted(1), true);
});

test("you stay in charge: unmuting during an interruption sticks", async () => {
  const tabs = fakeTabs({ 1: { muted: false } });
  const muter = createMuter(tabs, ID);
  await muter.report(1, true);
  tabs.userSets(1, false);
  await muter.report(1, false);
  assert.equal(tabs.muted(1), false);
});

test("muting again yourself during an interruption sticks after it ends", async () => {
  const tabs = fakeTabs({ 1: { muted: false } });
  const muter = createMuter(tabs, ID);
  await muter.report(1, true);
  tabs.userSets(1, true);
  await muter.report(1, false);
  assert.equal(tabs.muted(1), true);
});

test("a quick start and end are applied in order", async () => {
  const tabs = fakeTabs({ 1: { muted: false } });
  const muter = createMuter(tabs, ID);
  muter.report(1, true);
  await muter.report(1, false);
  assert.equal(tabs.muted(1), false);
});

test("a page that loads mid-interruption mutes; one that loads after unmutes", async () => {
  const tabs = fakeTabs({ 1: { muted: true, reason: "extension", extensionId: ID } });
  const muter = createMuter(tabs, ID);
  await muter.report(1, false);
  assert.equal(tabs.muted(1), false);
});

test("leaves tabs muted by another extension alone", async () => {
  const tabs = fakeTabs({ 1: { muted: true, reason: "extension", extensionId: "someone-else" } });
  const muter = createMuter(tabs, ID);
  await muter.report(1, false);
  assert.equal(tabs.muted(1), true);
});

test("a closed tab is ignored", async () => {
  const muter = createMuter(fakeTabs(), ID);
  await assert.doesNotReject(muter.report(99, true));
});

test("after an update, gives back the sound of every tab it muted, and only those", async () => {
  const tabs = fakeTabs({
    1: { muted: true, reason: "extension", extensionId: ID },
    2: { muted: true, reason: "user" },
    3: { muted: false },
  });
  await createMuter(tabs, ID).releaseAll();
  assert.deepEqual([tabs.muted(1), tabs.muted(2), tabs.muted(3)], [false, true, false]);
});
