# frozen_string_literal: true

require_relative 'test_helper'
require 'rack/test'

begin
  require 'rails'
  require 'action_controller/railtie'
  require 'action_view/railtie'
rescue LoadError
  warn 'railties/actionpack not installed; skipping Railtie tests'
end

if defined?(::Rails::Railtie)
  ENV['RAILS_ENV'] = 'test'
  require 'vue_live/railtie'

  class VueLiveTestApp < ::Rails::Application
    config.root = FIXTURES
    config.eager_load = false
    config.logger = Logger.new(File::NULL)
    config.secret_key_base = 'x' * 64
    config.hosts.clear if config.respond_to?(:hosts)
    config.public_file_server.enabled = true
    config.vue_live.compiler = :ruby
    config.vue_live.import_map = { 'pinia' => '/pinia.js' }

    routes.append do
      get '/page', to: proc { |env|
        view = ActionView::Base.with_empty_template_cache.with_view_paths([], {}, nil)
        html = view.render(inline: <<~ERB)
          <%= vue_live_import_map_tag %>
          <%= vue_live_mount_tag 'App.vue', '#app', props: { title: 'Rails' }, element: true %>
        ERB
        [200, { 'content-type' => 'text/html' }, [html]]
      }
    end
  end

  VueLiveTestApp.initialize!

  class RailtieTest < Minitest::Test
    include Rack::Test::Methods

    def app
      VueLiveTestApp
    end

    def test_configuration_comes_from_rails
      assert_equal FIXTURES, VueLive.config.root
      assert_equal 'test', VueLive.config.env
      assert_equal :ruby, VueLive.config.compiler
      assert_equal({ 'pinia' => '/pinia.js' }, VueLive.config.import_map)
      assert_equal File.join(FIXTURES, 'app/vue'), VueLive.config.source_dir
    end

    def test_middleware_is_mounted_before_static
      names = VueLiveTestApp.middleware.map(&:name)
      assert_includes names, 'VueLive::Middleware'
      assert_operator names.index('VueLive::Middleware'), :<, names.index('ActionDispatch::Static')
    end

    def test_component_served_through_the_full_stack
      get '/vue/App.vue.js'
      assert_equal 200, last_response.status
      assert_equal 'text/javascript; charset=utf-8', last_response.headers['content-type']
      assert_includes last_response.body, '__sfc__.template'
      assert_includes last_response.body, 'data-v-'
    end

    def test_view_helpers_are_available_and_html_safe
      get '/page'
      assert_equal 200, last_response.status
      assert_includes last_response.body, '<script type="importmap">'
      assert_includes last_response.body, '"pinia":"/pinia.js"'
      assert_includes last_response.body, '<div id="app"></div>'
      assert_match(%r{import App from "/vue/App\.vue\.js\?v=[0-9a-f]+"}, last_response.body)
      assert_includes last_response.body, 'createApp(App, {"title":"Rails"})'
      refute_includes last_response.body, '&lt;script'
    end

    def test_rake_tasks_are_registered
      require 'rake'
      Rake.application = Rake::Application.new
      Rake::Task.define_task(:environment)
      VueLiveTestApp.load_tasks
      %w[vue_live:precompile vue_live:clobber vue_live:check vue_live:node_setup].each do |name|
        assert Rake::Task.task_defined?(name), "expected rake task #{name}"
      end
    end

    def test_generator_is_loadable
      require 'generators/vue_live/install/install_generator'
      assert VueLive::Generators::InstallGenerator < ::Rails::Generators::Base
    end
  end
end

if defined?(::Rails::Railtie)
  class InstallGeneratorTest < Minitest::Test
    def test_generator_creates_files
      require 'generators/vue_live/install/install_generator'
      Dir.mktmpdir do |dir|
        VueLive::Generators::InstallGenerator.start(['--quiet'], destination_root: dir)
        assert File.file?(File.join(dir, 'config/vue_live.yml'))
        assert File.file?(File.join(dir, 'app/vue/HelloVueLive.vue'))
        yaml = YAML.safe_load(File.read(File.join(dir, 'config/vue_live.yml')), aliases: true)
        assert_equal 'app/vue', yaml['default']['source_path']
        assert_equal 'auto', yaml['default']['compiler']
      end
    end
  end
end
