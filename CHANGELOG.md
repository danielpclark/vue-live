# Changelog

## 0.1.0 (unreleased)

* Pure Ruby `.vue` compiler: `<template>`, `<script>`, `<style>` / `<style scoped>` (`:deep`,
  `:slotted`, `:global`), `src="..."` attributes, relative `.vue` import rewriting.
* Optional Node backend via `@vue/compiler-sfc`: `<script setup>`, TypeScript, preprocessors,
  CSS modules.  `compiler: auto` picks per component.
* Rack middleware with ETags, digested immutable URLs, HEAD support, path confinement, and a
  development error overlay module.
* Memory and file caches with mtime-based reloading.
* Framework-agnostic helpers, Sinatra extension, Rails Railtie (middleware, helpers with CSP
  nonces, `config.vue_live`, `config/vue_live.yml`, generator, rake tasks, importmap-rails pin).
* Precompiler writing static `.vue.js` modules and a manifest.
* `vue-live` CLI: `init`, `compile`, `clobber`, `check`, `node-setup`, `info`.
* Development live reload over Server-Sent Events (`<prefix>/-/events`, `<prefix>/-/reload.js`),
  included automatically by `vue_live_mount_tag`.
* Persistent Node worker for the Node backend (a few ms per compile after start-up).
* Digested relative imports (`./Child.vue.js?v=<digest>`) so the whole module graph can be cached
  immutably; import cycles handled.
* Inline source maps from both backends (Ruby: script block line for line; Node: merged script and
  template maps).
* `rake test:setup` installs the Node packages and Chromium the optional tests need; those tests
  auto-detect them instead of requiring environment variables.
* RuboCop configuration and CI job.
* TypeScript on Node.js < 22.13: `rake test:setup` and `vue-live node-setup` install sucrase when
  Node cannot strip types itself, `VUE_LIVE_TS_TRANSPILER` pins a transpiler, `vue-live check`
  warns about the gap, and CI covers Node 20 (#3).
