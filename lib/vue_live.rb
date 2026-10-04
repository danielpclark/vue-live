# frozen_string_literal: true

require_relative 'vue_live/version'
require_relative 'vue_live/errors'
require_relative 'vue_live/configuration'
require_relative 'vue_live/compiler'
require_relative 'vue_live/emitter'
require_relative 'vue_live/cache'
require_relative 'vue_live/resolver'
require_relative 'vue_live/store'
require_relative 'vue_live/middleware'
require_relative 'vue_live/helpers'
require_relative 'vue_live/precompiler'
require_relative 'vue_live/node_tools'

# vue_live: serve Vue single-file components straight from Ruby, in production, with no build step.
#
#   # Rack / Sinatra
#   use VueLive::Middleware
#
#   # Rails: nothing to do - the Railtie mounts the middleware and adds the view helpers.
#
#   <%= vue_live_import_map_tag %>
#   <%= vue_live_mount_tag 'App.vue', '#app' %>
module VueLive
  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config if block_given?
      reset_store!
      config
    end

    # Replace the configuration wholesale (used by tests and by the Railtie).
    def config=(configuration)
      @config = configuration
      reset_store!
    end

    # Load config/vue_live.yml from the project root if it exists.
    def load_config_file(path = nil)
      config.load_yaml(*[path].compact)
      reset_store!
      config
    end

    # The object that compiles and caches components; one per configuration.
    def store
      @store ||= Store.new(config)
    end

    def reset_store!
      @store = nil
    end

    # Compile a component by its path relative to the source directory and return the module body.
    def compile(relative_path)
      store.fetch(relative_path).code
    end

    # Convenience: compile a .vue string with no file behind it.
    def compile_source(source, filename: 'anonymous.vue')
      result = Compiler.compile(source, relative_path: filename, config: config)
      Emitter.emit(result, relative_path: filename, inject_styles: config.inject_styles)
    end

    # ---- environment detection -------------------------------------------------------------

    def rails?
      defined?(::Rails) && ::Rails.respond_to?(:application) && !::Rails.application.nil?
    rescue StandardError
      false
    end

    # A Rails project on disk (even when Rails itself is not loaded, e.g. from the CLI).
    def rails_project?(dir = Dir.pwd)
      File.file?(File.join(dir, 'config', 'application.rb')) &&
        (File.file?(File.join(dir, 'bin', 'rails')) || File.file?(File.join(dir, 'config', 'environment.rb')))
    end

    def sinatra?
      defined?(::Sinatra::Base) ? true : false
    end

    def detect_root
      return ::Rails.root.to_s if rails? && ::Rails.root
      ENV['VUE_LIVE_ROOT'] || Dir.pwd
    end

    def detect_env
      ENV['VUE_LIVE_ENV'] || ENV['RAILS_ENV'] || ENV['RACK_ENV'] || ENV['APP_ENV'] ||
        (rails? ? ::Rails.env.to_s : 'development')
    end

    def logger
      config.logger
    end
  end
end

require_relative 'vue_live/railtie' if defined?(::Rails::Railtie)
