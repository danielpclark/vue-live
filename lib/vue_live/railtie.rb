# frozen_string_literal: true

require 'rails/railtie'
require_relative '../vue_live'
require_relative 'rails/helper'

module VueLive
  # Wires vue_live into a Rails application with no configuration:
  #
  #   * `config.vue_live` exposes every Configuration option (config.vue_live.prefix = '/components')
  #   * config/vue_live.yml is read when present (`rails g vue_live:install` writes one)
  #   * the middleware is mounted ahead of the asset pipeline's static file server, answering
  #     only `/vue/...`, so Sprockets, Propshaft, Webpacker and jsbundling keep their own paths
  #   * view helpers are added to ActionView
  #   * when importmap-rails is present, `vue` is pinned into the app's import map
  #   * rake tasks: vue_live:precompile, vue_live:clobber, vue_live:check, vue_live:node_setup
  class Railtie < ::Rails::Railtie
    config.vue_live = ActiveSupport::OrderedOptions.new

    # Make `Rails.root`, `Rails.env` and `Rails.logger` the source of truth before anything reads them.
    initializer 'vue_live.configure', before: :load_environment_config do |app|
      VueLive.config.root = app.root.to_s
      VueLive.config.env = ::Rails.env.to_s
      VueLive.config.logger = ::Rails.logger if ::Rails.logger
    end

    initializer 'vue_live.apply_configuration', after: :load_environment_config do |app|
      VueLive.config.root = app.root.to_s
      VueLive.config.env = ::Rails.env.to_s
      VueLive.load_config_file
      VueLive.config.apply(app.config.vue_live.to_h)
      VueLive.reset_store!
    end

    initializer 'vue_live.middleware' do |app|
      app.config.after_initialize do
        VueLive.config.logger ||= ::Rails.logger
      end
      next unless app.config.vue_live.fetch(:middleware, true)

      if defined?(::ActionDispatch::Static) && app.middleware.respond_to?(:insert_before)
        begin
          app.middleware.insert_before ::ActionDispatch::Static, VueLive::Middleware
        rescue StandardError
          app.middleware.use VueLive::Middleware
        end
      else
        app.middleware.use VueLive::Middleware
      end
    end

    initializer 'vue_live.helpers' do
      ActiveSupport.on_load(:action_view) { include VueLive::Rails::Helper }
    end

    initializer 'vue_live.importmap', after: 'importmap' do |app|
      next unless defined?(::Importmap) && app.respond_to?(:importmap)
      app.config.after_initialize do
        next unless VueLive.config.importmap_pin
        map = app.importmap
        next if map.packages.key?('vue')
        map.draw { pin 'vue', to: VueLive.config.resolved_vue_url, preload: true }
      end
    end

    rake_tasks do
      load File.expand_path('tasks.rake', __dir__)
    end

    generators do
      require_relative '../generators/vue_live/install/install_generator'
    end
  end
end
