# frozen_string_literal: true

require_relative 'test_helper'

class PrecompilerTest < Minitest::Test
  def test_writes_modules_assets_and_manifest
    with_tmp_app do |dir|
      cfg = fresh_config(root: dir, compiler: :ruby, precompile_path: 'public/out')
      FileUtils.mkdir_p(File.join(dir, 'node_modules/vue/dist'))
      File.write(File.join(dir, 'node_modules/vue/dist/vue.esm-browser.js'), '// vue')
      manifest = VueLive::Precompiler.new(cfg).run(quiet: true)

      out = File.join(dir, 'public/out')
      assert File.file?(File.join(out, 'App.vue.js'))
      assert File.file?(File.join(out, 'nested/Child.vue.js'))
      assert File.file?(File.join(out, 'shared/util.js'))
      assert File.file?(File.join(out, '-/vue.esm-browser.js'))
      refute File.exist?(File.join(out, 'secret.txt'))
      assert_match(%r{from './nested/Child\.vue\.js\?v=[0-9a-f]{16}'}, File.read(File.join(out, 'App.vue.js')))

      json = JSON.parse(File.read(File.join(out, 'manifest.json')))
      assert_equal manifest, json
      assert_match(%r{\A/vue/App\.vue\.js\?v=[0-9a-f]{16}\z}, json['App.vue'])
      assert_equal '/vue/shared/util.js', json['shared/util.js']
      refute json.key?('Broken.vue')
      refute File.exist?(File.join(out, 'Broken.vue.js'))
    end
  end

  def test_reports_failures_and_can_be_strict
    with_tmp_app do |dir|
      cfg = fresh_config(root: dir, compiler: :ruby)
      pre = VueLive::Precompiler.new(cfg)
      pre.run(quiet: true)
      assert_equal 2, pre.errors.size # Broken.vue (syntax) and Setup.vue (<script setup> needs Node)
      assert_raises(VueLive::CompileError) { VueLive::Precompiler.new(cfg).run(quiet: true, strict: true) }
    end
  end

  def test_clobber
    with_tmp_app do |dir|
      cfg = fresh_config(root: dir, compiler: :ruby)
      VueLive::Precompiler.new(cfg).run(quiet: true)
      assert Dir.exist?(cfg.precompile_dir)
      VueLive::Precompiler.new(cfg).clobber
      refute Dir.exist?(cfg.precompile_dir)
    end
  end
end
