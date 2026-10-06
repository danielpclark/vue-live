# frozen_string_literal: true

require_relative '../vue_live'

module VueLive
  # Sinatra extension:
  #
  #   require 'vue_live/sinatra'
  #   class App < Sinatra::Base
  #     set :vue_live, source_path: 'app/vue', prefix: '/vue'   # optional, before register
  #     register VueLive::Sinatra
  #   end
  #
  # Classic-style apps call `register VueLive::Sinatra` at the top level.
  #
  # Mounts the middleware (unless config.middleware is false), defaults the component root to the
  # app's own root and adds the view helpers.
  module Sinatra
    def self.registered(app)
      app.helpers VueLive::Helpers
      app.set :vue_live, {} unless app.respond_to?(:vue_live)

      app.configure do
        VueLive.config.root = app.root if app.respond_to?(:root) && app.root && !VueLive.rails?
        VueLive.config.env = app.environment.to_s if app.respond_to?(:environment) && app.environment
        VueLive.config.apply(app.vue_live || {})
        VueLive.load_config_file
        app.use VueLive::Middleware if VueLive.config.middleware
      end
    end
  end
end
