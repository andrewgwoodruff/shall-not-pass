// Runs in the page, after the site's detector (src/sites/*.js). Watches the
// page for changes and tells the background script whenever the page goes
// from content to an interruption or back. It never touches the page itself.
(() => {
  const site = globalThis.shallNotPassSite;
  let last = null;

  // Some sites start the next track a moment before the page shows what it
  // is. For those, the tab goes quiet the instant a track changes and stays
  // quiet until the page shows the new track, so the start of an interruption
  // is never heard. Content gets its sound back as soon as it's on screen.
  const HOLD_MAX_MS = 3000; // if the page never changes, e.g. the same song again
  let hold = null;

  window.addEventListener("shall-not-pass:track-change", () => {
    if (!site.nowPlaying) return;
    clearTimeout(hold?.timer);
    hold = { from: site.nowPlaying(document), timer: setTimeout(release, HOLD_MAX_MS) };
    check();
  });

  function release() {
    clearTimeout(hold?.timer);
    hold = null;
    check();
  }

  function isInterrupted() {
    if (hold && site.nowPlaying(document) === hold.from) return true;
    if (hold) {
      clearTimeout(hold.timer);
      hold = null;
    }
    return Boolean(site.isInterrupted(document));
  }

  function check() {
    const interrupted = isInterrupted();
    if (interrupted === last) return;
    last = interrupted;
    if (!chrome.runtime?.id) {
      // The extension was reloaded or updated; this copy of the script is orphaned.
      observer.disconnect();
      clearInterval(backstop);
      return;
    }
    chrome.runtime.sendMessage({ type: "shall-not-pass", interrupted }).catch(() => {});
  }

  // Changes are reported the moment the page updates. The slow backstop only
  // matters if the page changes in a way the observer doesn't see.
  const observer = new MutationObserver(check);
  observer.observe(document.documentElement, {
    subtree: true,
    childList: true,
    characterData: true,
    attributes: true,
    attributeFilter: ["class", "href"],
  });
  const backstop = setInterval(check, 1000);

  // Always report once on load, so a tab left muted by a page that went away
  // mid-interruption gets its sound back.
  check();
})();
