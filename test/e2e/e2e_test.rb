# frozen_string_literal: true

require_relative '../test_helper'
require 'open3'
require 'socket'
require 'json'
require 'timeout'

# Runs whenever `rake test:setup` has installed playwright-core and a Chromium (or
# PLAYWRIGHT_CHROMIUM names a browser); set VUE_LIVE_E2E=0 to skip it explicitly.
class E2ETest < Minitest::Test
  def setup
    skip 'VUE_LIVE_E2E=0 disables the browser test' if ENV['VUE_LIVE_E2E'] == '0'
    skip 'run `rake test:setup` to install @vue/compiler-sfc, sass and playwright-core' unless node_available?
    @chromium = chromium_path
    skip 'no Chromium found: run `rake test:setup` or set PLAYWRIGHT_CHROMIUM' unless @chromium
  end

  def test_components_render_in_a_real_browser
    port = free_port
    server = Process.spawn(RbConfig.ruby, File.expand_path('server.rb', __dir__), NODE_ROOT, port.to_s, err: File::NULL)
    wait_for_port(port)
    out, err, status = Timeout.timeout(120) do
      Open3.capture3({ 'PLAYWRIGHT_CHROMIUM' => @chromium }, 'node', File.expand_path('browser.js', __dir__), NODE_ROOT, "http://127.0.0.1:#{port}/")
    end
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
    assert seen['liveReload'], 'live reload client should be active in development'
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
