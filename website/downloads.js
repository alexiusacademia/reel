// Reel website: fills the download buttons from downloads.json (written by
// tools/publish.sh), and counts a download when one is pressed: the product,
// version and system go to the statistics service, nothing about the visitor
// (see privacy.html).
//
// Author: Alexius Academia
// Date: 2026-10-27

(function () {
  function fill(feed) {
    for (const system of ['macos', 'windows']) {
      const entry = (feed || {})[system] || {}
      const button = document.querySelector('[data-download="' + system + '"]')
      const note = document.querySelector('[data-size="' + system + '"]')
      if (!button || !entry.url) continue
      const link = document.createElement('a')
      link.className = 'btn primary'
      link.href = entry.url
      link.textContent = 'Download ' + entry.version
      button.replaceWith(link)
      if (note && entry.size) {
        note.textContent = (entry.size / 1048576).toFixed(1) + ' MB'
      }
    }
    const version = ((feed || {}).macos || {}).version || ((feed || {}).windows || {}).version
    const line = document.getElementById('release-line')
    if (version && line) {
      line.textContent = 'Reel ' + version + '. Free to download and open source.'
    }
  }

  fetch('downloads.json', { cache: 'no-cache' })
    .then((r) => (r.ok ? r.json() : {}))
    .then(fill)
    .catch(() => {})

  document.addEventListener('click', (event) => {
    const link = event.target.closest ? event.target.closest('a[href]') : null
    if (!link) return
    const found = /storage\.googleapis\.com\/reel-releases\/(?:.*\/)?v?(\d+(?:\.\d+)+)\/[^/]+\.(dmg|exe)$/.exec(link.href)
    if (!found) return
    const system = found[2] === 'exe' ? 'windows' : 'macos'
    const ping = 'https://stats.syncster.dev/v1/ping?app=reel&type=download&v=' + found[1] + '&os=' + system
    if (navigator.sendBeacon) navigator.sendBeacon(ping)
    else new Image().src = ping
  })
})()
