# frozen_string_literal: true

require_relative '../test_helper'
require 'open3'
require 'socket'
require 'json'

# Opt-in: VUE_LIVE_E2E=1 VUE_LIVE_NODE_ROOT=<dir with vue, @vue/compiler-sfc, sass, playwright-core>
# Set PLAYWRIGHT_CHROMIUM to a Chromium binary when playwright-core has not downloaded one.
class E2ETest < Minitest::Test
  def setup
    skip 'set VUE_LIVE_E2E=1 to run the browser test' unless ENV['VUE_LIVE_E2E']
    skip 'VUE_LIVE_NODE_ROOT must point at a project with playwright-core' unless NODE_ROOT && File.directory?(File.join(NODE_ROOT, 'node_modules', 'playwright-core'))
  end

  def test_components_render_in_a_real_browser
    port = free_port
    server = Process.spawn(RbConfig.ruby, File.expand_path('server.rb', __dir__), NODE_ROOT, port.to_s, err: File::NULL)
    wait_for_port(port)
    out, err, status = Open3.capture3('node', File.expand_path('browser.js', __dir__), NODE_ROOT, "http://127.0.0.1:#{port}/")
    assert status.success?, err
    seen = JSON.parse(out)

    assert_equal 'E2E', seen['h1']
    assert_equal 'rgb(66, 184, 131)', seen['h1Color'], 'scoped style from App.vue'
    assert_equal 'rgb(255, 0, 0)', seen['childColor'], 'scoped style from Child.vue'
    assert_equal 'rgb(0, 0, 0)', seen['outsideColor'], 'scoped style must not leak'
    assert_equal '0px', seen['bodyMargin'], 'global style from Child.vue'
    assert_equal 'n = 3', seen['childText'], 'events and reactivity'
    assert seen['many'], 'nested <template v-if>'
    assert_equal '42', seen['setupText'], '<script setup> via the Node backend'
    assert_equal 'rgb(0, 0, 255)', seen['setupColor'], 'scoped scss via the Node backend'
    assert_empty seen['errors']
  ensure
    Process.kill('TERM', server) if server
    Process.wait(server) if server
  end

  private

  def free_port
    s = TCPServer.new('127.0.0.1', 0)
    s.addr[1]
  ensure
    s&.close
  end

  def wait_for_port(port)
    50.times do
      TCPSocket.new('127.0.0.1', port).close
      return
    rescue Errno::ECONNREFUSED
      sleep 0.2
    end
    flunk 'e2e server did not start'
  end
end
