// YouTube: the video player carries the class "ad-showing" (YouTube's own
// name) for as long as an interruption plays, including several in a row.
globalThis.shallNotPassSite = {
  name: "YouTube",
  isInterrupted(doc) {
    return doc.querySelector("#movie_player")?.classList.contains("ad-showing") ?? false;
  },
};
