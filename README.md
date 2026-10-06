# vue_live

[![CI](https://github.com/danielpclark/vue_live/actions/workflows/ci.yml/badge.svg)](https://github.com/danielpclark/vue_live/actions/workflows/ci.yml)

**Serve Vue single-file components straight from Ruby, in production, with no build step.**

Drop a `.vue` file into `app/vue/`, render one helper in a view, and the browser gets a native ES
module.  No bundler, no watcher, no Node.js unless you want it.

```erb
<%# app/views/layouts/application.html.erb, once, in <head> %>
<%= vue_live_import_map_tag %>

<%# any view %>
<%= vue_live_mount_tag 'HelloVueLive.vue', '#app', props: { name: current_user.name }, element: true %>
```

## Contents

* [Why vue_live](#why-vue_live)
* [Installation](#installation)
* [Quick start: Rails](#quick-start-rails)
* [Quick start: Sinatra](#quick-start-sinatra)
* [Quick start: plain Rack](#quick-start-plain-rack)
* [Writing components](#writing-components)
* [Pinia, Vue Router and other packages](#pinia-vue-router-and-other-packages)
* [Helpers](#helpers)
* [Compiler backends](#compiler-backends)
* [Development: live reload, errors, source maps](#development-live-reload-errors-source-maps)
* [Caching, production and deployment](#caching-production-and-deployment)
* [Browser support and trade-offs](#browser-support-and-trade-offs)
* [Vue 2](#vue-2)
* [Configuration reference](#configuration-reference)
* [Command line and rake tasks](#command-line-and-rake-tasks)
* [Security notes](#security-notes)
* [Contributing](#contributing)
* [License](#license)

## Why vue_live

Back when Rails shipped Sprockets and Webpacker, a `.vue` file could be translated on the fly and
served to a running site.  `vue_live` brings that back for modern Vue (3.x) and modern browsers,
without tying itself to Rails or to any asset pipeline.

* **Pure Ruby compiler, zero runtime dependencies.**  A `.vue` file is parsed in Ruby, its
  `<template>` is handed to Vue's own in-browser compiler, `<style scoped>` selectors are rewritten
  the way `@vue/compiler-sfc` does, and the result is served as a native ES module.
* **Works anywhere Rack does.**  Rails, Sinatra, Roda, Hanami, plain `config.ru`.
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
# Until the first release is on RubyGems:
# gem 'vue_live', github: 'danielpclark/vue_live'
```

Requires Ruby 3.0+.  Node.js is **not** required unless you opt into the
[Node backend](#compiler-backends).

## Quick start: Rails

```sh
bin/rails generate vue_live:install
```

The generator writes `config/vue_live.yml` and an example `app/vue/HelloVueLive.vue`.  Pass
`--node` to also install the Node backend, or `--skip-example` to leave `app/vue/` empty.

Render the import map once, in your layout's `<head>`, and mount components from any view:

```erb
<%# app/views/layouts/application.html.erb %>
<%= vue_live_import_map_tag %>   <%# omit when you use importmap-rails, see below %>

<%# app/views/pages/home.html.erb %>
<%= vue_live_mount_tag 'HelloVueLive.vue', '#app', props: { name: current_user.name }, element: true %>
```

That is the whole setup.  `app/vue/HelloVueLive.vue` is compiled on first request and served at
`/vue/HelloVueLive.vue.js`.  In development it recompiles whenever the file changes and the page
reloads itself.

Settings live in `config/vue_live.yml` (written by the generator) or in Ruby, which takes
precedence:

```ruby
# config/application.rb
config.vue_live.source_path = 'app/components'   # default: app/vue
config.vue_live.prefix      = '/components'      # default: /vue
config.vue_live.compiler    = :node              # :auto (default), :ruby or :node
config.vue_live.cache       = :file              # :memory (default), :file or :none
```

### Rails + importmap-rails

Browsers honour only one `<script type="importmap">` per page.  When importmap-rails is present,
`vue_live_import_map_tag` renders nothing and the Railtie pins `vue` into *your* import map
instead.  Keep using `javascript_importmap_tags`.  Set `config.vue_live.importmap_pin = false` to
opt out and manage the two separately.

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
  set :vue_live, source_path: 'app/vue', prefix: '/vue'   # optional, must come before register
  register VueLive::Sinatra

  get '/' do
    <<~HTML
      <!doctype html>
      #{vue_live_import_map_tag}
      #{vue_live_mount_tag 'App.vue', '#app', props: { title: 'Sinatra' }, element: true}
    HTML
  end
end
```

`register` reads `settings.vue_live`, mounts the middleware and adds the helpers, so any
`set :vue_live` has to come first.  `config/vue_live.yml` is read as well, if present.
Classic-style apps (`require 'sinatra'`) call `register VueLive::Sinatra` at the top level.

`vue_live init` scaffolds `config/vue_live.yml` and `app/vue/HelloVueLive.vue` in any project.

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

## Writing components

A component is an ordinary Vue SFC.  Relative imports to other components and to plain `.js`
files under the component root just work:

```vue
<template>
  <button class="counter" @click="count++">{{ label }}: {{ count }}</button>
  <Child />
</template>

<script>
import Child from './nested/Child.vue'
import { shout } from './shared/util.js'

export default {
  components: { Child },
  props: { label: String },
  data() { return { count: 0 } },
  methods: { yell() { alert(shout(this.label)) } }
}
</script>

<style scoped>
.counter { color: #42b883; }
</style>
```

With the Ruby backend the served module is, in essence:

```js
import Child from './nested/Child.vue.js?v=9c1e…'
import { shout } from './shared/util.js?v=1718-412'
const __sfc__ = { components: { Child }, props: { label: String }, data() { return { count: 0 } }, methods: { … } }
__sfc__.template = "<button class=\"counter\" @click=\"count++\">{{ label }}: {{ count }}</button>\n<Child />"
__sfc__.__scopeId = "data-v-5d1a9f3c"
export default __sfc__
/* + a few lines that register ".counter[data-v-5d1a9f3c] { color: #42b883 }" once */
```

Vue compiles the template string in the browser (so the import map must point at a *full* build,
`vue.esm-browser.js`, which is the default) and applies the scope id in its renderer, so scoped
styles need no build step either.

**Shared files.**  Anything under `source_path` with an allowed extension is served as-is from the
same prefix: `.js` and `.mjs` modules, `.css`, `.json`, images and fonts.  So `app/vue/shared/util.js`
is importable from any component and `app/vue/img/logo.svg` is reachable at `/vue/img/logo.svg`.
Blocks can also point at files with `src="..."`, e.g. `<style src="./shared/theme.css">`.

**Several components on one page.**  Render `vue_live_import_map_tag` once, in the layout, and as
many `vue_live_mount_tag`s as you like with different selectors.  Each becomes its own small Vue
app:

```erb
<%= vue_live_mount_tag 'Search.vue', '#search', element: true %>
<%= vue_live_mount_tag 'Cart.vue',   '#cart',   props: { items: @cart.as_json }, element: true %>
```

**Props** are passed as JSON, so anything `JSON.generate` accepts works.  `element: true` renders
the mount `<div>` for you; leave it off when the element is already in your markup.

## Pinia, Vue Router and other packages

Components can import any bare specifier that the page's import map resolves.  Add entries with
`import_map` in `config/vue_live.yml` (or `config.vue_live.import_map`), or per page with
`vue_live_import_map_tag(imports: { ... })`:

```yaml
default:
  import_map:
    pinia:      https://esm.sh/pinia@3?external=vue
    vue-router: https://esm.sh/vue-router@4?external=vue
```

`?external=vue` keeps the package's own `import ... from 'vue'` bare, so it resolves through the
import map to the same Vue instance your components use.  Any CDN works as long as the build you
pick does not bundle its own copy of Vue.  With importmap-rails, pin the packages there instead.

Then write the mount script yourself with `vue_live_module_tag` and `vue_live_path`:

```erb
<div id="app"></div>
<%= vue_live_module_tag "
  import { createApp } from 'vue'
  import { createPinia } from 'pinia'
  import App from '#{vue_live_path('App.vue')}'

  createApp(App).use(createPinia()).mount('#app')
" %>
```

Inside components, `import { defineStore } from 'pinia'` and `import { useRouter } from 'vue-router'`
work exactly as they would under a bundler.  Under Rails the module tag picks up the CSP nonce
automatically.

## Helpers

| Helper | Purpose |
| --- | --- |
| `vue_live_import_map_tag(imports: {})` | `<script type="importmap">` mapping `vue` plus `config.import_map` and `imports`.  Once per page, before any module script.  Renders nothing under importmap-rails. |
| `vue_live_mount_tag(component, selector = '#app', props: {}, element: false, plugins: [], nonce: nil)` | `<script type="module">` that imports the component and mounts it on `selector`.  Adds the live-reload client in development. |
| `vue_live_module_tag(js)` | `<script type="module">` for your own code (custom mounts, routers, stores). |
| `vue_live_path(component)` | `/vue/App.vue.js?v=<digest>`, read from the manifest when precompiled. |
| `vue_live_tags(component, selector, **)` | Import map + mount tag in one call, for single-component pages. |
| `vue_live_reload_tag` | The live-reload client on its own.  Renders nothing when `live_reload` is off. |

`plugins:` takes JavaScript expressions that are appended as `app.use(...)` calls.  The generated
script imports only `vue` and the component, so this suits globals you have already loaded; for
anything that needs its own import, write the mount script with `vue_live_module_tag` as shown
above.

Under Rails the helpers return `html_safe` strings and pick up the CSP nonce automatically.
Outside Rails they return plain strings; pass `nonce:` yourself if you use a CSP.

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
first compile (which includes Node's start-up) each component takes a few milliseconds.  The
worker is restarted automatically if it dies; set `node_worker: false` to spawn a process per
compile instead.

Enable the Node backend with:

```sh
vue_live node-setup                 # npm/yarn add @vue/compiler-sfc vue
vue_live node-setup --with sass     # plus preprocessors you use
bin/rails vue_live:node_setup       # the same, under Rails
```

Installing `vue` locally also makes `vue_live` serve it from `/vue/-/vue.esm-browser.js` instead
of the CDN.  If the [webpacker_cli](https://github.com/danielpclark/webpacker-cli) gem is
installed its package manager detection is reused, so projects already built with it need
nothing extra.

**TypeScript.**  Node.js 22.13+ strips types itself.  On older Node.js a transpiler package is
needed; `vue_live node-setup` adds [sucrase](https://github.com/alangpierce/sucrase) automatically
in that case (pure JavaScript, keeps line numbers so source maps stay exact).
`VUE_LIVE_TS_TRANSPILER=node|sucrase|esbuild|typescript|babel` pins one when several are
installed, and `vue_live check` warns when a Node.js that cannot strip types has no transpiler.

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

## Caching, production and deployment

* `reload` (default: on outside production) compares mtimes on every request and recompiles
  changed files, including `src="..."` dependencies and imported siblings.
* `digest_imports` (default: on) rewrites the relative imports inside a module to
  `./Child.vue.js?v=<digest>` and `./util.js?v=<mtime-size>`, so a page's whole module graph can
  be served with `Cache-Control: immutable`.  A child's digest is part of its parent's code, so a
  change anywhere propagates up to the URL the page requests.  Import cycles are handled (the
  back edge stays undigested and revalidates by ETag).
* `cache: :memory` (default) keeps compiled modules per process.  `cache: :file` also writes them
  to `tmp/cache/vue_live` so Puma workers and restarts share the work.
* Responses carry an `ETag`; URLs from `vue_live_path` include `?v=<digest>` and are served with
  `Cache-Control: public, max-age=31536000, immutable` in production.
* In production a component that fails to compile is a 500 with the details in the log.
* `vue_live compile` / `bin/rails vue_live:precompile` writes every component as a static
  `.vue.js` file plus `manifest.json` to `public/vue`, for a CDN or `nginx`.  When the manifest
  exists in production, `vue_live_path` reads URLs from it, so a web server or CDN in front of
  `public/` serves the files and the app never compiles them.  Without one, the middleware still
  answers from its cache.

**Deploying.**  Three setups work, pick the one that fits your host:

| Setup | What to do | Good for |
| --- | --- | --- |
| Compile at runtime, memory cache | Nothing.  Each process compiles on first request. | Read-only filesystems, small apps, few processes |
| Compile at runtime, file cache | `cache: file` in `config/vue_live.yml`; `tmp/` must be writable. | Puma clusters, frequent restarts |
| Precompile | Run `bin/rails vue_live:precompile` in your build (Dockerfile, CI, or `hook_assets_precompile: true`). | CDNs, `nginx` serving `public/`, zero compile cost at runtime |

In production the CDN URL switches to `vue.esm-browser.prod.js` automatically, and
`vue_live check` / `bin/rails vue_live:check` verifies that every component compiles before you ship.

## Browser support and trade-offs

`vue_live` relies on two browser features: native ES modules and import maps.  Import maps are
supported in Chrome and Edge 89+, Firefox 108+ and Safari 16.4+ (March 2023).  Older browsers can
be covered with [es-module-shims](https://github.com/guybedford/es-module-shims) if you need them.

Serving modules unbundled is a deliberate trade:

* **One request per module.**  Fine over HTTP/2 for a page that loads a few dozen files; a
  component tree in the hundreds is better served precompiled behind a CDN, or bundled.
* **No tree shaking or minification of your own code.**  Vue itself comes minified from the CDN;
  your components are served as written.
* **The Ruby backend compiles templates in the browser.**  That needs Vue's full build, which is
  larger than the runtime-only build, and costs a little CPU on first render.  The Node backend
  precompiles templates to render functions and removes both costs.

If you are already running Vite or esbuild and are happy with it, keep it.  `vue_live` is for
the many apps where a build step is the only reason Node.js is installed.

## Vue 2

The Ruby backend's output is also valid for Vue 2.7's full build (`_scopeId` is emitted alongside
`__scopeId`).  Set `vue_version: 2.7.16` and `vue_url` to a Vue 2 ESM build and
`vue_live_mount_tag` emits `new Vue({ render: h => h(App) }).$mount(...)`.  Vue 2 is end-of-life,
so Vue 3 is the default and the only version the Node backend supports.

## Configuration reference

Values come from built-in defaults, then `config/vue_live.yml` (the `default` section merged with
the current environment's section), then Ruby (`VueLive.configure` or `config.vue_live`).

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
| `node_bin` | `node` | Node executable |
| `precompile_path` | `public/vue` | output of `vue_live compile` |
| `use_manifest` | auto | read `public/vue/manifest.json` for URLs (auto: in production when it exists) |
| `middleware` | `true` | mount automatically (Railtie / Sinatra); set `false` to `use` it yourself |
| `importmap_pin` | `true` | pin `vue` into importmap-rails |
| `hook_assets_precompile` | `false` | run `vue_live:precompile` with `assets:precompile` |
| `inject_styles` | `true` | emit `<style>` blocks into the module |
| `source_maps` | not production | append an inline source map to each module |
| `node_worker` | `true` | keep one long-lived Node worker instead of a process per compile |
| `live_reload` / `live_reload_interval` | follows `reload` / `0.5` | SSE live reload and its scan interval in seconds |
| `digest_imports` | `true` | add `?v=<digest>` to relative imports inside modules |

Environment variables:

| Variable | Meaning |
| --- | --- |
| `VUE_LIVE_ENV`, `RAILS_ENV`, `RACK_ENV`, `APP_ENV` | environment name, first one set wins (default `development`) |
| `VUE_LIVE_NODE` | Node executable, same as `node_bin` |
| `VUE_LIVE_TS_TRANSPILER` | `node`, `sucrase`, `esbuild`, `typescript` or `babel` |

## Command line and rake tasks

The gem ships a `vue_live` executable for any project and the same operations as rake tasks
under Rails:

| `vue_live` | Rails | Does |
| --- | --- | --- |
| `init [--force] [--node]` | `bin/rails generate vue_live:install [--node] [--skip-example]` | create `config/vue_live.yml` and `app/vue/HelloVueLive.vue` |
| `compile [--out DIR]` | `bin/rails vue_live:precompile` | write static `.vue.js` modules + `manifest.json` |
| `clobber` | `bin/rails vue_live:clobber` | remove precompiled output and the compile cache |
| `check` | `bin/rails vue_live:check` | compile every component and verify the Node toolchain; exits non-zero on problems |
| `node-setup [--with pkg,pkg]` | `bin/rails vue_live:node_setup` | install `@vue/compiler-sfc` and `vue` (plus sucrase when Node.js < 22.13) |
| `info` | | print versions and the resolved settings |

## Security notes

Everything under `source_path` with an allowed extension is public.  Keep secrets out of it.
Paths are normalised and confined to that directory; dot-files and unknown extensions are refused.

## Contributing

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
