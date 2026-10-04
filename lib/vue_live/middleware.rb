# frozen_string_literal: true

require 'time'

module VueLive
  # Rack middleware answering requests under the configured prefix (default "/vue"):
  #
  #   GET /vue/App.vue            -> compiled ES module (also at /vue/App.vue.js)
  #   GET /vue/components/x.js    -> any other allowed file under the component root, as-is
  #   GET /vue/-/vue.esm-browser.js -> a local copy of Vue when the project has one
  #
  # Everything else is passed to the next app, so it can sit in front of Sprockets, Propshaft,
  # Webpacker or ActionDispatch::Static without interfering with them.
  #
  #   use VueLive::Middleware                      # uses VueLive.config
  #   use VueLive::Middleware, prefix: '/components', source_path: 'lib/vue'
  class Middleware
    MIME = {
      '.vue' => 'text/javascript; charset=utf-8',
      '.js' => 'text/javascript; charset=utf-8',
      '.mjs' => 'text/javascript; charset=utf-8',
      '.css' => 'text/css; charset=utf-8',
      '.json' => 'application/json; charset=utf-8',
      '.svg' => 'image/svg+xml',
      '.png' => 'image/png',
      '.jpg' => 'image/jpeg',
      '.jpeg' => 'image/jpeg',
      '.gif' => 'image/gif',
      '.webp' => 'image/webp',
      '.avif' => 'image/avif',
      '.ico' => 'image/x-icon',
      '.woff' => 'font/woff',
      '.woff2' => 'font/woff2',
      '.ttf' => 'font/ttf',
      '.otf' => 'font/otf'
    }.freeze

    attr_reader :config

    def initialize(app, options = {})
      @app = app
      options = options.dup
      if (cfg = options.delete(:config))
        @config = cfg
      elsif options.empty?
        @config = VueLive.config
      else
        @config = VueLive.config.dup.apply(options)
      end
      # Share the global store when running on the global config so VueLive.store.clear works.
      @store = @config.equal?(VueLive.config) ? nil : Store.new(@config)
    end

    def store
      @store || VueLive.store
    end

    def call(env)
      path = env['PATH_INFO'].to_s
      prefix = config.normalized_prefix
      return @app.call(env) unless path.start_with?("#{prefix}/")
      return method_not_allowed unless %w[GET HEAD].include?(env['REQUEST_METHOD'])

      rest = path[(prefix.length + 1)..]
      return serve_vendor(env, rest) if rest.start_with?('-/')

      target = store.resolver.resolve(rest)
      return @app.call(env) unless target

      target.vue? ? serve_component(env, target) : serve_file(env, target)
    end

    private

    def serve_component(env, target)
      compiled = store.fetch(target.relative_path)
      return not_modified if fresh?(env, compiled.etag)
      headers = {
        'content-type' => MIME['.vue'],
        'etag' => compiled.etag,
        'cache-control' => cache_control(env, compiled.digest),
        'x-vue-live' => compiled.backend.to_s
      }
      respond(env, 200, headers, compiled.code)
    rescue CompileError => e
      config.logger.error("[vue_live] #{e.message}")
      if config.production?
        respond(env, 500, { 'content-type' => 'text/plain; charset=utf-8', 'cache-control' => 'no-store' },
                "vue_live: failed to compile #{target.relative_path}\n")
      else
        respond(env, 200, { 'content-type' => MIME['.vue'], 'cache-control' => 'no-store' }, error_module(e))
      end
    end

    def serve_file(env, target)
      stat = File.stat(target.absolute_path)
      etag = %("#{stat.mtime.to_i.to_s(16)}-#{stat.size.to_s(16)}")
      return not_modified if fresh?(env, etag)
      ext = File.extname(target.relative_path).downcase
      headers = {
        'content-type' => MIME.fetch(ext, 'application/octet-stream'),
        'etag' => etag,
        'last-modified' => stat.mtime.httpdate,
        'cache-control' => cache_control(env, etag.delete('"'))
      }
      respond(env, 200, headers, File.binread(target.absolute_path))
    end

    # /vue/-/vue.esm-browser.js : serve the project's own copy of Vue when there is one.
    def serve_vendor(env, rest)
      return @app.call(env) unless rest == '-/vue.esm-browser.js' && (file = config.local_vue_file)
      stat = File.stat(file)
      etag = %("vue-#{stat.size.to_s(16)}-#{stat.mtime.to_i.to_s(16)}")
      return not_modified if fresh?(env, etag)
      headers = { 'content-type' => MIME['.js'], 'etag' => etag, 'cache-control' => cache_control(env, etag.delete('"')) }
      respond(env, 200, headers, File.binread(file))
    end

    # Digested URLs (?v=<digest>) are immutable; plain URLs must revalidate.
    def cache_control(env, digest)
      query = env['QUERY_STRING'].to_s
      if query.match?(/(?:\A|&)v=#{Regexp.escape(digest)}(?:&|\z)/) && !config.reload?
        'public, max-age=31536000, immutable'
      else
        'no-cache'
      end
    end

    def fresh?(env, etag)
      inm = env['HTTP_IF_NONE_MATCH']
      inm && inm.split(',').map(&:strip).include?(etag)
    end

    def not_modified
      [304, { 'cache-control' => 'no-cache' }, []]
    end

    def method_not_allowed
      [405, { 'content-type' => 'text/plain', 'allow' => 'GET, HEAD' }, ['Method Not Allowed']]
    end

    def respond(env, status, headers, body)
      body = body.to_s
      headers['content-length'] = body.bytesize.to_s
      [status, headers, env['REQUEST_METHOD'] == 'HEAD' ? [] : [body]]
    end

    # In development a broken component becomes a module that throws a readable error, so the
    # failure shows up in the browser console (and in Vue's error overlay if any) instead of a
    # bare network error.
    def error_module(error)
      message = Emitter.js_string("[vue_live] #{error.message}")
      <<~JS
        const message = #{message}
        console.error(message)
        if (typeof document !== 'undefined') {
          const pre = document.createElement('pre')
          pre.setAttribute('data-vue-live-error', '')
          pre.style.cssText = 'position:fixed;left:0;right:0;bottom:0;margin:0;padding:16px;max-height:50vh;overflow:auto;z-index:2147483647;background:#300;color:#fdd;font:13px/1.4 monospace;white-space:pre-wrap;'
          pre.textContent = message
          document.body ? document.body.appendChild(pre) : document.addEventListener('DOMContentLoaded', () => document.body.appendChild(pre))
        }
        throw new Error(message)
      JS
    end
  end
end
