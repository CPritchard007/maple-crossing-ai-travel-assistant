(() => {
  let closeUrl = null;
  window.mapleInstanceLifecycle = (url) => { closeUrl = url; };
  window.addEventListener('pagehide', (event) => {
    // A page in the back-forward cache may return with the same running app.
    if (!event.persisted && closeUrl) {
      navigator.sendBeacon(closeUrl, '');
    }
  });
})();
