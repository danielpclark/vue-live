# frozen_string_literal: true

require 'fileutils'
require 'json'

module VueLive
  # Writes every component as a static `.vue.js` module (plus sibling assets and a manifest) so
  # a CDN or plain file server can serve them.  Optional: the middleware is the normal path.
  #
  #   VueLive::Precompiler.new.run            #=> public/vue/App.vue.js, public/vue/manifest.json
  #
  # The manifest maps "App.vue" => "/vue/App.vue.js?v=<digest>" and is used by vue_live_path when
  # config.use_manifest? is true.
  class Precompiler
    attr_reader :config, :store, :errors

    def initialize(config = VueLive.config, store: nil)
      @config = config
      @store = store || Store.new(config)
    end

    # Compiles everything it can.  Components that fail are reported (and collected in #errors);
    # pass strict: true to raise on the first failure instead.
    def run(output: config.precompile_dir, quiet: false, strict: false, out: $stdout)
      FileUtils.mkdir_p(output)
      manifest = {}
      @errors = errors = []
      prefix = config.normalized_prefix

      store.resolver.files.each do |rel|
        src = File.join(store.resolver.source_dir, rel)
        if rel.end_with?('.vue')
          begin
            compiled = store.fetch(rel)
          rescue Error => e
            errors << e
            out.puts "  FAIL   #{rel}: #{e.message}" unless quiet
            next
          end
          dest = File.join(output, "#{rel}.js")
          write(dest, compiled.code)
          manifest[rel] = "#{prefix}/#{rel}.js?v=#{compiled.digest}"
        else
          dest = File.join(output, rel)
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(src, dest)
          manifest[rel] = "#{prefix}/#{rel}"
        end
        out.puts "  write  #{dest}" unless quiet
      end

      if (vue = config.local_vue_file)
        dest = File.join(output, '-', 'vue.esm-browser.js')
        FileUtils.mkdir_p(File.dirname(dest))
        FileUtils.cp(vue, dest)
        out.puts "  write  #{dest}" unless quiet
      end

      write(File.join(output, 'manifest.json'), JSON.pretty_generate(manifest))
      raise errors.first if strict && errors.any?

      manifest
    end

    def clobber(output: config.precompile_dir)
      FileUtils.rm_rf(output)
    end

    def self.manifest(config = VueLive.config)
      @manifests ||= {}
      path = config.manifest_path
      return @manifests[path] if @manifests[path] && !config.reload?

      @manifests[path] = File.file?(path) ? JSON.parse(File.read(path)) : {}
    end

    def self.reset!
      @manifests = {}
    end

    private

    def write(dest, content)
      FileUtils.mkdir_p(File.dirname(dest))
      File.write(dest, content)
    end
  end
end
