# frozen_string_literal: true

require 'yaml'
require 'logger'

module VueLive
  # All tunables live here.  Values come from (lowest to highest precedence):
  #
  #   1. built-in defaults
  #   2. config/vue_live.yml  (``default`` section merged with the current environment section)
  #   3. Ruby: VueLive.configure { |c| ... }  /  Rails: config.vue_live.xxx = ...
  #
  # Everything is plain Ruby so it works the same under Rails, Sinatra or bare Rack.
  class Configuration
    VUE_VERSION   = '3.5.43'
    CDN_TEMPLATE  = 'https://cdn.jsdelivr.net/npm/vue@%<version>s/dist/%<file>s'

    # Files the middleware is willing to serve from the component root.  Everything else is 404.
    DEFAULT_EXTENSIONS = %w[.vue .js .mjs .css .json .svg .png .jpg .jpeg .gif .webp .avif .ico .woff .woff2 .ttf .otf].freeze

    # Where the project lives.  Rails.root under Rails, the current directory elsewhere.
    attr_writer :root
    # Directory holding the .vue components, relative to +root+ (or absolute).
    attr_accessor :source_path
    # URL prefix the middleware answers on.
    attr_accessor :prefix
    # Current environment name: development / test / production.
    attr_writer :env
    # :ruby (pure Ruby, zero dependencies), :node (@vue/compiler-sfc through Node.js) or :auto
    # (Ruby, falling back to Node only for components the Ruby backend cannot handle).
    attr_accessor :compiler
    # Re-check mtimes and recompile changed files on every request.  On in development and test.
    attr_accessor :reload
    # :memory keeps compiled modules in the process, :file additionally persists them under
    # +cache_path+ (survives restarts, shared between workers), :none disables caching.
    attr_accessor :cache
    attr_accessor :cache_path, :vue_version
    attr_writer :logger
    # URL of the Vue ESM build.  nil = auto: a local copy under node_modules or vendor/vue_live when
    # present, otherwise the pinned jsDelivr build.  Must be a *full* build (with the template
    # compiler) when components ship their templates as strings, i.e. with the Ruby backend.
    attr_accessor :vue_url
    # Extra entries for the generated import map, e.g. { 'pinia' => 'https://...' }.
    attr_accessor :import_map
    # Node.js executable used by the :node compiler.
    attr_accessor :node_bin
    # Allowed file extensions under +source_path+.
    attr_accessor :extensions
    # Output directory for +vue_live compile+ (precompiled, static ES modules).
    attr_accessor :precompile_path
    # Use public/vue/manifest.json for URLs instead of the live middleware.  nil = auto
    # (true in production when the manifest exists).
    attr_accessor :use_manifest
    # Mount the middleware automatically (Railtie / Sinatra extension).  Set false to +use+ it yourself.
    attr_accessor :middleware
    # Register a `vue` pin with importmap-rails automatically when that gem is present.
    attr_accessor :importmap_pin
    # Hook `vue_live:precompile` into `assets:precompile` under Rails (off by default: live is the point).
    attr_accessor :hook_assets_precompile
    # Whether to emit `<style>` content into the module (true) or drop styles entirely (false).
    attr_accessor :inject_styles
    # Append an inline source map to every compiled module.  nil = on outside production.
    attr_accessor :source_maps
    # Keep one long-lived `node compile.js --server` process per configuration (true) or spawn a
    # process per compile (false).
    attr_accessor :node_worker
    # Development live reload: SSE stream at <prefix>/-/events + client at <prefix>/-/reload.js.
    # nil = on whenever +reload+ is on.
    attr_accessor :live_reload
    # Seconds between directory scans for live reload.
    attr_accessor :live_reload_interval
    # Add `?v=<digest>` to the relative imports inside compiled modules so every file a page loads
    # can be cached immutably.
    attr_accessor :digest_imports

    def initialize
      @root         = nil
      @source_path  = 'app/vue'
      @prefix       = '/vue'
      @env          = nil
      @compiler     = :auto
      @reload       = nil
      @cache        = :memory
      @cache_path   = 'tmp/cache/vue_live'
      @vue_url      = nil
      @vue_version  = VUE_VERSION
      @import_map   = {}
      @node_bin     = ENV['VUE_LIVE_NODE'] || 'node'
      @extensions   = DEFAULT_EXTENSIONS.dup
      @precompile_path = 'public/vue'
      @use_manifest = nil
      @middleware   = true
      @logger       = nil
      @importmap_pin = true
      @hook_assets_precompile = false
      @inject_styles = true
      @source_maps  = nil
      @node_worker  = true
      @live_reload  = nil
      @live_reload_interval = 0.5
      @digest_imports = true
    end

    def root
      @root ||= VueLive.detect_root
    end

    def env
      @env ||= VueLive.detect_env
    end

    def production?
      env.to_s == 'production'
    end

    def reload?
      @reload.nil? ? !production? : !!@reload
    end

    def source_maps?
      @source_maps.nil? ? !production? : !!@source_maps
    end

    def live_reload?
      @live_reload.nil? ? reload? : !!@live_reload
    end

    def logger
      @logger ||= default_logger
    end

    def source_dir
      File.expand_path(source_path.to_s, root)
    end

    def cache_dir
      File.expand_path(cache_path.to_s, root)
    end

    def precompile_dir
      File.expand_path(precompile_path.to_s, root)
    end

    def manifest_path
      File.join(precompile_dir, 'manifest.json')
    end

    def use_manifest?
      return !!@use_manifest unless @use_manifest.nil?

      production? && File.exist?(manifest_path)
    end

    # Normalised prefix: leading slash, no trailing slash ("/vue").
    def normalized_prefix
      p = "/#{prefix.to_s.gsub(%r{\A/+|/+\z}, '')}"
      p == '/' ? '' : p
    end

    # The URL the browser loads Vue itself from.
    def resolved_vue_url
      return vue_url if vue_url && !vue_url.empty?
      return "#{normalized_prefix}/-/vue.esm-browser.js" if local_vue_file

      format(CDN_TEMPLATE, version: vue_version, file: production? ? 'vue.esm-browser.prod.js' : 'vue.esm-browser.js')
    end

    # A copy of Vue's full ESM browser build inside the project, if one is installed.
    def local_vue_file
      candidates = [
        File.join(root, 'vendor', 'vue_live', production? ? 'vue.esm-browser.prod.js' : 'vue.esm-browser.js'),
        File.join(root, 'vendor', 'vue_live', 'vue.esm-browser.js'),
        File.join(root, 'node_modules', 'vue', 'dist', production? ? 'vue.esm-browser.prod.js' : 'vue.esm-browser.js'),
        File.join(root, 'node_modules', 'vue', 'dist', 'vue.esm-browser.js')
      ]
      candidates.find { |f| File.file?(f) }
    end

    # Merge a config/vue_live.yml (``default`` + env sections) into this object.
    def load_yaml(file = File.join(root, 'config', 'vue_live.yml'))
      return self unless File.file?(file)

      data = YAML.safe_load_file(file, aliases: true, symbolize_names: false) || {}
      merged = (data['default'] || {}).merge(data[env.to_s] || {})
      apply(merged)
    end

    # Apply a Hash of settings (string or symbol keys).
    def apply(hash)
      hash.each do |key, value|
        setter = "#{key}="
        next unless respond_to?(setter)

        value = value.to_sym if %w[compiler cache].include?(key.to_s) && value.is_a?(String)
        public_send(setter, value)
      end
      self
    end

    def to_h
      instance_variables.each_with_object({}) do |ivar, h|
        name = ivar.to_s.delete('@')
        next if name == 'logger'

        h[name] = instance_variable_get(ivar)
      end
    end

    private

    def default_logger
      if defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger
        ::Rails.logger
      else
        Logger.new($stderr).tap { |l| l.level = production? ? Logger::INFO : Logger::DEBUG }
      end
    end
  end
end
