# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
ENV['VUE_LIVE_ENV'] ||= 'test'

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'logger'
require 'open3'
require 'vue_live'

FIXTURES = File.expand_path('fixtures', __dir__)

# Directory whose node_modules holds @vue/compiler-sfc (and sass, playwright-core) for the optional
# Node-backend and browser tests.  `rake test:setup` installs them into test/; VUE_LIVE_NODE_ROOT
# overrides the location.  Without either, those tests skip with a message.
NODE_ROOT = ENV['VUE_LIVE_NODE_ROOT'] || [__dir__, File.expand_path('..', __dir__)].find do |dir|
  File.directory?(File.join(dir, 'node_modules', '@vue', 'compiler-sfc'))
end

module VueLiveTestHelpers
  def fresh_config(**overrides)
    cfg = VueLive::Configuration.new
    cfg.root = FIXTURES
    cfg.env = 'test'
    cfg.logger = Logger.new(File::NULL)
    overrides.each { |k, v| cfg.public_send("#{k}=", v) }
    cfg
  end

  # Install a fresh global configuration for the duration of a test.
  def with_global_config(**overrides)
    previous = VueLive.config
    VueLive.config = fresh_config(**overrides)
    yield VueLive.config
  ensure
    VueLive.config = previous
  end

  # Copy the fixture app to a temp directory so tests can modify files.
  def with_tmp_app
    Dir.mktmpdir('vue_live') do |dir|
      FileUtils.cp_r(File.join(FIXTURES, 'app'), dir)
      yield dir
    end
  end

  def node_available?
    return false unless NODE_ROOT

    cfg = fresh_config(root: NODE_ROOT, compiler: :node)
    VueLive::Compiler::Node.available?(cfg)
  end

  # A Chromium playwright-core can launch: PLAYWRIGHT_CHROMIUM, or the browser `rake test:setup`
  # downloaded.  nil when neither exists.
  def chromium_path
    return ENV['PLAYWRIGHT_CHROMIUM'] if ENV['PLAYWRIGHT_CHROMIUM'] && File.executable?(ENV['PLAYWRIGHT_CHROMIUM'])
    return nil unless NODE_ROOT && File.directory?(File.join(NODE_ROOT, 'node_modules', 'playwright-core'))

    out, status = Open3.capture2('node', '-e', "console.log(require('playwright-core').chromium.executablePath())",
                                 chdir: NODE_ROOT)
    path = out.strip
    return path if status.success? && File.executable?(path)

    %w[chromium chromium-browser google-chrome google-chrome-stable chrome].each do |name|
      ENV['PATH'].to_s.split(File::PATH_SEPARATOR).each do |dir|
        candidate = File.join(dir, name)
        return candidate if File.executable?(candidate) && !File.directory?(candidate)
      end
    end
    nil
  rescue Errno::ENOENT
    nil
  end
end

Minitest::Test.include VueLiveTestHelpers
