// Mutes and unmutes tabs. Chrome records who muted a tab, and that record is
// the only state: a tab is "ours" while Chrome says this extension muted it.
// Nothing is stored, so nothing can go stale.
//
// - A tab you muted yourself is never touched.
// - Unmute a tab during an interruption and it stays unmuted until the
//   interruption ends; Chrome then says you, not we, set its sound.
// - Reports for one tab are handled in order, so a quick start-then-end can't
//   finish in the wrong order.
globalThis.createMuter = (tabs, extensionId) => {
  const queues = new Map();

  const mutedByUs = (tab) =>
    tab.mutedInfo?.muted === true &&
    tab.mutedInfo.reason === "extension" &&
    tab.mutedInfo.extensionId === extensionId;

  async function apply(tabId, interrupted) {
    let tab;
    try {
      tab = await tabs.get(tabId);
    } catch {
      return; // the tab closed
    }
    if (interrupted && !tab.mutedInfo?.muted) {
      await tabs.update(tabId, { muted: true });
    } else if (!interrupted && mutedByUs(tab)) {
      await tabs.update(tabId, { muted: false });
    }
  }

  return {
    report(tabId, interrupted) {
      const next = (queues.get(tabId) ?? Promise.resolve()).then(() => apply(tabId, interrupted)).catch(() => {});
      queues.set(tabId, next);
      next.then(() => {
        if (queues.get(tabId) === next) queues.delete(tabId);
      });
      return next;
    },

    // After an install or update, pages are still running the old content
    // scripts, which can no longer report. Give back the sound of any tab we
    // muted rather than risk leaving it silent.
    async releaseAll() {
      for (const tab of await tabs.query({ muted: true })) {
        if (mutedByUs(tab)) await tabs.update(tab.id, { muted: false }).catch(() => {});
      }
    },
  };
};
