# frozen_string_literal: true

require_relative 'test_helper'

class NodeToolsTest < Minitest::Test
  def test_node_strips_types_threshold
    tools = VueLive::NodeTools
    stub = ->(version) { tools.stub(:node_version, version) { tools.node_strips_types?(fresh_config) } }
    refute stub.call('v20.20.2')
    refute stub.call('v22.12.0')
    assert stub.call('v22.13.0')
    assert stub.call('v23.0.0')
    assert stub.call('v24.1.0')
    refute stub.call(nil)
  end

  def test_installed_ts_transpilers
    Dir.mktmpdir do |dir|
      assert_empty VueLive::NodeTools.installed_ts_transpilers(dir)
      FileUtils.mkdir_p(File.join(dir, 'node_modules', 'sucrase'))
      FileUtils.mkdir_p(File.join(dir, 'node_modules', '@babel', 'core'))
      assert_equal ['sucrase', '@babel/core'], VueLive::NodeTools.installed_ts_transpilers(dir)
    end
  end

  def test_problems_warn_about_missing_transpiler_on_old_node
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'app', 'vue'))
      cfg = fresh_config(root: dir, compiler: :auto)
      VueLive::NodeTools.stub(:node_version, 'v20.20.2') do
        assert(VueLive::NodeTools.problems(cfg).any? { |p| p.include?('cannot strip TypeScript') })
      end
      VueLive::NodeTools.stub(:node_version, 'v22.13.0') do
        assert_empty VueLive::NodeTools.problems(cfg)
      end
      FileUtils.mkdir_p(File.join(dir, 'node_modules', 'esbuild'))
      VueLive::NodeTools.stub(:node_version, 'v20.20.2') do
        assert_empty VueLive::NodeTools.problems(cfg)
      end
    end
  end
end
