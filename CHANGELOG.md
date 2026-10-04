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
