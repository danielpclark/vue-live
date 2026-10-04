# frozen_string_literal: true

require 'rails/generators'

module VueLive
  module Generators
    # rails generate vue_live:install
    #
    # Creates app/vue/ with an example component, config/vue_live.yml and prints how to render it.
    class InstallGenerator < ::Rails::Generators::Base
      source_root File.expand_path('../../../vue_live/templates', __dir__)

      class_option :node, type: :boolean, default: false,
                          desc: 'Also install @vue/compiler-sfc and vue with npm/yarn (enables <script setup>, TypeScript, Sass)'
      class_option :skip_example, type: :boolean, default: false, desc: 'Do not create app/vue/HelloVueLive.vue'

      def create_config
        template 'vue_live.yml', 'config/vue_live.yml'
      end

      def create_component_directory
        empty_directory 'app/vue'
        copy_file 'HelloVueLive.vue', 'app/vue/HelloVueLive.vue' unless options[:skip_example]
      end

      def setup_node
        return unless options[:node]

        require 'vue_live/node_tools'
        VueLive::NodeTools.setup(destination_root)
      end

      def show_readme
        say ''
        say 'vue_live is installed.  Render a component from any view:', :green
        say ''
        say '    <%= vue_live_import_map_tag %>' unless defined?(::Importmap)
        say '    <%= vue_live_mount_tag "HelloVueLive.vue", "#app", props: { name: "Rails" }, element: true %>'
        say ''
        if defined?(::Importmap)
          say 'importmap-rails detected: `vue` has been pinned into your import map automatically;'
          say 'keep using javascript_importmap_tags in your layout.'
          say ''
        end
        say 'Components live in app/vue/ and are served live from /vue/<Name>.vue.js.'
        say 'Settings: config/vue_live.yml or config.vue_live.* in config/application.rb.'
      end
    end
  end
end
