// vue_live development live-reload client.  Served at <prefix>/-/reload.js, listens to the
// server-sent events at <prefix>/-/events and reloads the page when a component changes.
;(function () {
  if (typeof window === 'undefined' || window.__vueLiveReload) return
  window.__vueLiveReload = true
  var script = document.currentScript
  var url = (script && script.getAttribute('data-events')) || '/vue/-/events'
  var source
  var reconnectDelay = 1000

  function connect() {
    source = new EventSource(url)
    source.addEventListener('change', function (event) {
      try {
        var files = JSON.parse(event.data).files || []
        console.info('[vue_live] changed: ' + files.join(', ') + ' — reloading')
      } catch (e) { /* ignore */ }
      window.location.reload()
    })
    source.addEventListener('open', function () { reconnectDelay = 1000 })
    source.addEventListener('error', function () {
      // The server went away (restart) or the stream timed out; EventSource retries on its own,
      // but a closed source needs a fresh one.
      if (source.readyState === EventSource.CLOSED) {
        setTimeout(connect, reconnectDelay)
        reconnectDelay = Math.min(reconnectDelay * 2, 10000)
      }
    })
  }

  connect()
})()
