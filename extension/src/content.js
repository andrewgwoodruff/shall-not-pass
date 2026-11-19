// Runs in the page, after the site's detector (src/sites/*.js). Watches the
// page for changes and tells the background script whenever the page goes
// from content to an interruption or back. It never touches the page itself.
(() => {
  const site = globalThis.shallNotPassSite;
  let last = null;

  function check() {
    const interrupted = Boolean(site.isInterrupted(document));
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
    attributes: true,
    attributeFilter: ["class", "href"],
  });
  const backstop = setInterval(check, 1000);

  // Always report once on load, so a tab left muted by a page that went away
  // mid-interruption gets its sound back.
  check();
})();
