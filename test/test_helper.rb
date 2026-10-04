# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
ENV['VUE_LIVE_ENV'] ||= 'test'

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'logger'
require 'vue_live'

FIXTURES = File.expand_path('fixtures', __dir__)
NODE_ROOT = ENV['VUE_LIVE_NODE_ROOT'] # a directory with node_modules/@vue/compiler-sfc, for Node backend tests

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
end

Minitest::Test.include VueLiveTestHelpers
