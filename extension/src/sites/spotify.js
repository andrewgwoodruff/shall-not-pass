// Spotify's web player: the now-playing bar links to the album and artist (or
// show and episode) of whatever is playing. During an interruption it links
// to the sponsor instead. Checking where the links go, rather than the text,
// keeps this working in every language.
(() => {
  const CONTENT = /^\/(album|artist|track|show|episode|audiobook|chapter|playlist|user|collection)\//;

  function isContent(href) {
    try {
      const url = new URL(href, "https://open.spotify.com");
      return url.hostname === "open.spotify.com" && CONTENT.test(url.pathname);
    } catch {
      return false;
    }
  }

  globalThis.shallNotPassSite = {
    name: "Spotify",
    isInterrupted(doc) {
      const bar = doc.querySelector('[data-testid="now-playing-widget-v2"], [data-testid="now-playing-widget"]');
      const links = bar ? [...bar.querySelectorAll("a[href]")] : [];
      if (links.length === 0) return false; // nothing playing, or still loading
      return !links.some((a) => isContent(a.getAttribute("href")));
    },
  };
})();
