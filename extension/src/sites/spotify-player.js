// Spotify's web player: the moment the player drops one track to load the
// next, before the next one makes a sound, tell content.js. The now-playing
// bar only shows what's next a fraction of a second after it starts playing,
// which is long enough to hear the start of an interruption.
//
// This runs in the page itself (not the extension's sandbox), because the
// player's audio element is never added to the page where the sandbox could
// see it. It only listens; it never changes playback.
(() => {
  if (window.__shallNotPassPlayer) return;
  window.__shallNotPassPlayer = true;

  const watched = new WeakSet();
  const announce = () => window.dispatchEvent(new CustomEvent("shall-not-pass:track-change"));

  const play = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = function (...args) {
    if (!watched.has(this)) {
      watched.add(this);
      this.addEventListener("emptied", announce);
    }
    return play.apply(this, args);
  };
})();
