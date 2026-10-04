# vue_live

**Serve Vue single-file components straight from Ruby, in production, with no build step.**

Back when Rails shipped Sprockets and Webpacker, a `.vue` file could be translated on the fly and
served to a running site.  `vue_live` brings that back for modern Vue (3.x) and modern browsers,
without tying itself to Rails or to any asset pipeline:

* **Pure Ruby compiler, zero runtime dependencies.**  A `.vue` file is parsed in Ruby, its
  `<template>` is handed to Vue's own in-browser compiler, `<style scoped>` selectors are rewritten
  the way `@vue/compiler-sfc` does, and the result is served as a native ES module.
* **Works anywhere Rack does.**  Sinatra, Roda, Hanami, plain `config.ru`.
* **Recognises a Rails application and configures itself.**  A Railtie mounts the middleware,
  adds view helpers, reads `config/vue_live.yml`, registers rake tasks and a generator, and pins
  `vue` into importmap-rails when present.
* **Coexists with your asset manager.**  Components live in `app/vue/` and are served from `/vue/`,
  so Sprockets, Propshaft, Webpacker, jsbundling and importmap-rails keep their own directories and
  URLs.  Nothing is registered with them and nothing of theirs is overridden.
* **Optional Node backend.**  Point it at a project with `@vue/compiler-sfc` installed and
  `<script setup>`, TypeScript, Pug, Sass/Less/Stylus and CSS modules work too.  The `auto`
  strategy only uses Node for components that need it.
* **Production ready.**  Compiled once per process (or persisted to disk), served with ETags,
  digested URLs with far-future caching for the whole import graph, and CSP-friendly style
  injection.  Optionally precompile everything to static files for a CDN.
* **Pleasant in development.**  Changed components recompile on the next request, the page
  reloads itself, compile errors show up in the page, and inline source maps point browser
  errors at the right line of the `.vue` file.

## Installation

```ruby
# Gemfile
gem 'vue_live'
```

Requires Ruby 3.0+.  Node.js is **not** required unless you opt into the Node backend (any
maintained Node.js works; see the TypeScript note below).

## Quick start: Rails

```sh
bin/rails generate vue_live:install        # config/vue_live.yml + app/vue/HelloVueLive.vue
```

Then in any view:

```erb
<%= vue_live_import_map_tag %>                    <%# omit when you use importmap-rails %>
<%= vue_live_mount_tag 'HelloVueLive.vue', '#app', props: { name: current_user.name }, element: true %>
```

That is the whole setup.  `app/vue/HelloVueLive.vue` is compiled on first request and served at
`/vue/HelloVueLive.vue.js`; in development it recompiles whenever the file changes and the page
reloads itself.

Settings can live in `config/vue_live.yml` (written by the generator) or in Ruby:

```ruby
# config/application.rb
config.vue_live.source_path = 'app/components'   # default app/vue
config.vue_live.prefix      = '/components'      # default /vue
config.vue_live.compiler    = :node              # :ruby (default-ish), :node, :auto (default)
config.vue_live.cache       = :file              # :memory (default), :file, :none
```

Rake tasks: `vue_live:precompile`, `vue_live:clobber`, `vue_live:check`, `vue_live:node_setup`.

### Rails + importmap-rails

Browsers honour only one `<script type="importmap">` per page, so when importmap-rails is present
`vue_live_import_map_tag` renders nothing and the Railtie pins `vue` into *your* import map instead
(`Rails.application.importmap.packages['vue']`).  Keep using `javascript_importmap_tags`.
Set `config.vue_live.importmap_pin = false` to opt out.

### Rails + Sprockets / Propshaft / Webpacker / jsbundling

Nothing to do.  `vue_live` never touches `app/assets`, `app/javascript`, `/assets` or `/packs`,
does not register `.vue` with Sprockets, and `vue_live:precompile` is **not** hooked into
`assets:precompile` unless you set `config.vue_live.hook_assets_precompile = true`.
The middleware is inserted before `ActionDispatch::Static` and only answers requests under its
prefix; everything else passes straight through.

## Quick start: Sinatra

```ruby
require 'sinatra/base'
require 'vue_live/sinatra'

class App < Sinatra::Base
  register VueLive::Sinatra
  set :vue_live, source_path: 'app/vue', prefix: '/vue'   # optional

  get '/' do
    <<~HTML
      <!doctype html>
      #{vue_live_import_map_tag}
      #{vue_live_mount_tag 'App.vue', '#app', props: { title: 'Sinatra' }, element: true}
    HTML
  end
end
```

Classic-style apps (`require 'sinatra'`) call `register VueLive::Sinatra` at the top level.
`vue-live init` scaffolds `config/vue_live.yml` and `app/vue/HelloVueLive.vue` in any project.

## Quick start: plain Rack

```ruby
# config.ru
require 'vue_live'
VueLive.configure { |c| c.source_path = 'app/vue' }
VueLive.load_config_file                       # config/vue_live.yml, if any

use VueLive::Middleware
run MyApp
```

Include `VueLive::Helpers` wherever you render HTML to get the tag helpers.

## What a component looks like

```vue
<template>
  <button class="counter" @click="count++">{{ label }}: {{ count }}</button>
</template>

<script>
import Child from './Child.vue'          // relative imports to other components just work

export default {
  components: { Child },
  props: { label: String },
  data() { return { count: 0 } }
}
</script>

<style scoped>
.counter { color: #42b883; }
</style>
```

With the Ruby backend the served module is, in essence:

```js
import Child from './Child.vue.js'
const __sfc__ = { components: { Child }, props: { label: String }, data() { return { count: 0 } } }
__sfc__.template = "<button class=\"counter\" @click=\"count++\">{{ label }}: {{ count }}</button>"
__sfc__.__scopeId = "data-v-5d1a9f3c"
export default __sfc__
/* + a few lines that register ".counter[data-v-5d1a9f3c] { color: #42b883 }" once */
```

Vue compiles the template string in the browser (so the import map must point at a *full* build,
`vue.esm-browser.js`, which is the default) and applies the scope id in its renderer, so scoped
styles need no build step either.

## Helpers

| Helper | Purpose |
| --- | --- |
| `vue_live_import_map_tag(imports: {})` | `<script type="importmap">` mapping `vue` (plus `config.import_map` and `imports`) |
| `vue_live_mount_tag(component, selector = '#app', props:, plugins:, element:, nonce:)` | `<script type="module">` that imports and mounts the component |
| `vue_live_module_tag(js)` | `<script type="module">` for your own code |
| `vue_live_path(component)` | `/vue/App.vue.js?v=<digest>`, from the manifest when precompiled |
| `vue_live_tags(component, selector, **)` | import map + mount tag in one call |

Under Rails the helpers are `html_safe` and pick up the CSP nonce automatically.

## Compiler backends

| | `:ruby` | `:node` |
| --- | --- | --- |
| Dependencies | none | Node.js + `@vue/compiler-sfc` in the project |
| `<template>` | string, compiled in the browser (needs Vue's full build) | render function (runtime-only Vue build is enough) |
| `<script>` | yes | yes |
| `<script setup>` | no | yes |
| `<script lang="ts">` | no | yes (types stripped by Node >= 22.13 itself, or by sucrase, esbuild, Babel or TypeScript < 7) |
| `<style>`, `<style scoped>` | yes (`:deep`, `:slotted`, `:global`) | yes |
| `<style lang="scss">`, `<style module>`, `<template lang="pug">` | no | yes, with the npm packages installed |
| `src="..."` on blocks | yes | yes |
| Speed | ~1 ms per component | ~400 ms once to start the worker, then a few ms per component |
| Source maps | script block, line for line | script and template, merged |

`compiler: auto` (the default) uses Ruby and falls back to Node only for components that need it,
with a clear error naming the feature when Node is unavailable.

The Node backend keeps one `node compile.js --server` worker per configuration, so after the
first compile (which includes Node's start-up, roughly 400 ms) each component takes a few
milliseconds.  The worker is restarted automatically if it dies; set `node_worker: false` to spawn
a process per compile instead.

Enable the Node backend with:

```sh
vue-live node-setup                 # npm/yarn add @vue/compiler-sfc vue
vue-live node-setup --with sass     # plus preprocessors you use
bin/rails vue_live:node_setup       # the same, under Rails
```

**TypeScript.**  Node.js 22.13+ strips types itself.  On older Node.js a transpiler package is
needed; `vue-live node-setup` adds [sucrase](https://github.com/alangpierce/sucrase) automatically
in that case (pure JavaScript, keeps line numbers so source maps stay exact), and
`VUE_LIVE_TS_TRANSPILER=node|sucrase|esbuild|typescript|babel` pins one when several are installed.
`vue-live check` warns when a Node.js that cannot strip types has no transpiler installed.

If the [webpacker_cli](https://github.com/danielpclark/webpacker-cli) gem is installed its package
manager detection is reused, so projects already built with it need nothing extra.  Installing
`vue` locally also makes `vue_live` serve it from `/vue/-/vue.esm-browser.js` instead of the CDN.

## Development: live reload, errors, source maps

* **Live reload.**  With `live_reload` on (the default whenever `reload` is on) `vue_live_mount_tag`
  adds a small client that listens to a Server-Sent Events stream at `/vue/-/events` and reloads
  the page when any file under the component root changes.  The stream is served by the
  middleware from the request's own thread, so it works with Puma, Falcon, WEBrick or anything
  else threaded, with no extra process.  `vue_live_reload_tag` renders the client on its own.
* **Errors in the page.**  A component that fails to compile is served as a module that logs the
  error, shows it in an overlay, and throws, so the failure is visible without opening the log.
* **Source maps.**  With `source_maps` on (the default outside production) every module ends with
  an inline source map.  The Ruby backend maps the `<script>` block line for line; the Node
  backend merges `@vue/compiler-sfc`'s script and template maps, so stack traces and breakpoints
  land in the `.vue` file.

## Caching and production

* `reload` (default: on outside production) compares mtimes on every request and recompiles
  changed files, including `src="..."` dependencies and imported siblings.
* `digest_imports` (default: on) rewrites the relative imports inside a module to
  `./Child.vue.js?v=<digest>` and `./util.js?v=<mtime-size>`, so a page's whole module graph can
  be served with `Cache-Control: immutable`.  A child's digest is part of its parent's code, so a
  change anywhere propagates up to the URL the page requests.  Import cycles are handled (the
  back edge stays undigested and revalidates by ETag).
* `cache: :memory` keeps compiled modules per process; `cache: :file` also writes them to
  `tmp/cache/vue_live` so Puma workers and restarts share the work.
* Responses carry an `ETag`; URLs from `vue_live_path` include `?v=<digest>` and are served with
  `Cache-Control: public, max-age=31536000, immutable` in production.
* In development a component that fails to compile is served as a module that throws a readable
  error (and shows it in the page); in production it is a 500 with the details in the log.
* `vue-live compile` / `rake vue_live:precompile` writes every component as a static `.vue.js`
  file plus `manifest.json` to `public/vue`, for a CDN or `nginx`.  When the manifest exists in
  production, `vue_live_path` reads from it.

## Vue 2

The Ruby backend's output is also valid for Vue 2.7's full build (`_scopeId` is emitted alongside
`__scopeId`).  Set `vue_version: 2.7.16` and `vue_url` to a Vue 2 ESM build and
`vue_live_mount_tag` emits `new Vue({ render: h => h(App) }).$mount(...)`.  Vue 2 is end-of-life,
so Vue 3 is the default and the only version the Node backend supports.

## Configuration reference

| Key | Default | Meaning |
| --- | --- | --- |
| `root` | `Rails.root` / `Dir.pwd` | project root |
| `source_path` | `app/vue` | component directory, relative to root |
| `prefix` | `/vue` | URL prefix |
| `compiler` | `auto` | `ruby`, `node` or `auto` |
| `reload` | not production | recompile on file change |
| `cache` / `cache_path` | `memory` / `tmp/cache/vue_live` | `memory`, `file`, `none` |
| `vue_url` | auto | local copy if present, else pinned jsDelivr build (`.prod.js` in production) |
| `vue_version` | pinned 3.x | version used for the CDN URL and Vue 2 detection |
| `import_map` | `{}` | extra import-map entries |
| `extensions` | `.vue .js .mjs .css .json` + images/fonts | files the middleware will serve from `source_path` |
| `node_bin` | `node` | Node executable (`VUE_LIVE_NODE`) |
| `precompile_path` | `public/vue` | output of `vue-live compile` |
| `use_manifest` | auto | read `public/vue/manifest.json` for URLs |
| `middleware` | `true` | mount automatically (Railtie / Sinatra) |
| `importmap_pin` | `true` | pin `vue` into importmap-rails |
| `hook_assets_precompile` | `false` | run `vue_live:precompile` with `assets:precompile` |
| `inject_styles` | `true` | emit `<style>` blocks into the module |
| `source_maps` | not production | append an inline source map to each module |
| `node_worker` | `true` | keep one long-lived Node worker instead of a process per compile |
| `live_reload` / `live_reload_interval` | follows `reload` / `0.5` | SSE live reload and its scan interval |
| `digest_imports` | `true` | add `?v=<digest>` to relative imports inside modules |

Environment: `VUE_LIVE_ENV`, `RAILS_ENV`, `RACK_ENV`, `APP_ENV` (default `development`).

## Security notes

Everything under `source_path` with an allowed extension is public.  Keep secrets out of it.
Paths are normalised and confined to that directory; dot-files and unknown extensions are refused.

## Development

```sh
bundle install
bundle exec rake test:setup   # npm install in test/ (+ a Chromium) for the Node-backend and browser tests
bundle exec rake test         # everything; without test:setup the Node and browser tests skip with a message
bundle exec rubocop
```

`VUE_LIVE_NODE_ROOT` points the Node tests at a different `node_modules`; `PLAYWRIGHT_CHROMIUM`
names a browser when Playwright could not download one; `VUE_LIVE_E2E=0` skips the browser test.

## License

Dual-licensed under either the [MIT License](LICENSE-MIT) or the
[Apache License, Version 2.0](LICENSE-APACHE), at your option.
