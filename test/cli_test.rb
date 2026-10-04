# frozen_string_literal: true

require_relative 'test_helper'
require 'vue_live/cli'
require 'stringio'

class CLITest < Minitest::Test
  def run_cli(*args, root:)
    out = StringIO.new
    previous = VueLive.config
    VueLive.config = fresh_config(root: root, compiler: :ruby)
    status = VueLive::CLI.new(args, out, StringIO.new).run
    [status, out.string]
  ensure
    VueLive.config = previous
  end

  def test_init_creates_files_and_detects_rails
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'config'))
      FileUtils.mkdir_p(File.join(dir, 'bin'))
      File.write(File.join(dir, 'config/application.rb'), '')
      File.write(File.join(dir, 'bin/rails'), '')
      status, out = run_cli('init', root: dir)
      assert_equal 0, status
      assert_includes out, 'Rails project detected'
      assert_includes out, 'create  config/vue_live.yml'
      assert File.file?(File.join(dir, 'app/vue/HelloVueLive.vue'))
      _, out = run_cli('init', root: dir)
      assert_includes out, 'exist  config/vue_live.yml'
    end
  end

  def test_compile_and_check
    with_tmp_app do |dir|
      status, out = run_cli('compile', '--out', 'public/vue', root: dir)
      assert_equal 0, status
      assert_includes out, 'App.vue.js'
      assert File.file?(File.join(dir, 'public/vue/manifest.json'))

      status, out = run_cli('check', root: dir)
      assert_equal 1, status # Broken.vue and Setup.vue cannot compile with Ruby
      assert_includes out, 'ok     App.vue (ruby)'
      assert_includes out, 'FAIL   Broken.vue'
    end
  end

  def test_info_version_and_unknown
    status, out = run_cli('info', root: FIXTURES)
    assert_equal 0, status
    assert_includes out, "vue_live: #{VueLive::VERSION}"
    assert_includes out, 'rails project: false'
    status, out = run_cli('version', root: FIXTURES)
    assert_equal 0, status
    assert_equal VueLive::VERSION, out.strip
    assert_equal 1, run_cli('bogus', root: FIXTURES).first
  end

  def test_config_file_is_loaded
    with_tmp_app do |dir|
      FileUtils.mkdir_p(File.join(dir, 'config'))
      File.write(File.join(dir, 'config/vue_live.yml'), "default:\n  prefix: /c\ntest:\n  compiler: ruby\n")
      _, out = run_cli('info', root: dir)
      assert_includes out, 'prefix: /c'
    end
  end
end
