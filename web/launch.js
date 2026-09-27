(() => {
  const splash = document.getElementById('launch-screen');
  const status = document.getElementById('launch-status');
  const slowLoad = setTimeout(() => {
    status.textContent = 'Still loading the map. Check your connection if this continues.';
  }, 45000);
  window.mapleLaunchReady = () => {
    if (!splash || splash.classList.contains('ready')) return;
    clearTimeout(slowLoad);
    splash.classList.add('ready');
    splash.setAttribute('aria-hidden', 'true');
    setTimeout(() => splash.remove(), 650);
  };
})();
