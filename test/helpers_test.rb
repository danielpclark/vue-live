# frozen_string_literal: true

require_relative 'test_helper'

class HelpersTest < Minitest::Test
  class View
    include VueLive::Helpers
  end

  def setup
    @view = View.new
  end

  def test_path_with_digest
    with_global_config(compiler: :ruby) do
      path = @view.vue_live_path('App.vue')
      assert_match(%r{\A/vue/App\.vue\.js\?v=[0-9a-f]{16}\z}, path)
      assert_equal '/vue/shared/util.js', @view.vue_live_path('shared/util.js')
      assert_equal '/vue/Missing.vue.js', @view.vue_live_path('Missing.vue')
    end
  end

  def test_import_map_tag
    with_global_config(import_map: { 'pinia' => 'https://x/pinia.js' }) do |cfg|
      tag = @view.vue_live_import_map_tag(imports: { extra: '/e.js' }, nonce: 'n1')
      assert tag.start_with?('<script type="importmap" nonce="n1">')
      map = JSON.parse(tag[/>(\{.*\})</, 1])
      assert_equal cfg.resolved_vue_url, map['imports']['vue']
      assert_equal 'https://cdn.jsdelivr.net/npm/vue@3.5.43/dist/vue.esm-browser.js', map['imports']['vue']
      assert_equal 'https://x/pinia.js', map['imports']['pinia']
      assert_equal '/e.js', map['imports']['extra']
    end
  end

  def test_production_uses_prod_build
    with_global_config(env: 'production') do |cfg|
      assert_equal 'https://cdn.jsdelivr.net/npm/vue@3.5.43/dist/vue.esm-browser.prod.js', cfg.resolved_vue_url
    end
  end

  def test_mount_tag
    with_global_config(compiler: :ruby) do
      tag = @view.vue_live_mount_tag('App.vue', '#root', props: { title: 'T</script>' }, element: true, plugins: ['pinia'])
      assert tag.start_with?('<div id="root"></div>')
      assert_includes tag, '<script type="module">'
      assert_includes tag, "import { createApp } from 'vue'"
      assert_match(%r{import App from "/vue/App\.vue\.js\?v=[0-9a-f]+"}, tag)
      assert_includes tag, 'createApp(App, {"title":"T<\/script>"})'
      assert_includes tag, 'app.use(pinia)'
      assert_includes tag, 'app.mount("#root")'
    end
  end

  def test_vue2_mount_tag
    with_global_config(vue_version: '2.7.16', compiler: :ruby) do
      tag = @view.vue_live_mount_tag('App.vue')
      assert_includes tag, "import Vue from 'vue'"
      assert_includes tag, 'new Vue({ render: h => h(App, { props: {} }) }).$mount("#app")'
    end
  end

  def test_tags_combines
    with_global_config(compiler: :ruby) do
      out = @view.vue_live_tags('App.vue')
      assert_includes out, 'type="importmap"'
      assert_includes out, 'type="module"'
    end
  end

  def test_manifest_mode
    with_tmp_app do |dir|
      with_global_config(root: dir, env: 'production', compiler: :ruby) do |cfg|
        VueLive::Precompiler.new(cfg).run(quiet: true)
        VueLive::Precompiler.reset!
        assert cfg.use_manifest?
        path = @view.vue_live_path('App.vue')
        assert_match(%r{\A/vue/App\.vue\.js\?v=[0-9a-f]{16}\z}, path)
        assert_equal JSON.parse(File.read(cfg.manifest_path))['App.vue'], path
        assert_equal '/vue/shared/util.js', @view.vue_live_path('shared/util.js')
      end
    end
  end
end
