importScripts("mute.js");

const muter = createMuter(chrome.tabs, chrome.runtime.id);

chrome.runtime.onMessage.addListener((message, sender) => {
  if (message?.type !== "shall-not-pass" || sender.tab?.id === undefined) return;
  // Only the top-level page speaks for a tab, never an embedded frame.
  if (sender.frameId !== 0) return;
  muter.report(sender.tab.id, message.interrupted === true);
});

chrome.runtime.onInstalled.addListener(() => muter.releaseAll());
