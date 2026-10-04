# frozen_string_literal: true

require_relative 'test_helper'
require 'rack/test'

class MiddlewareTest < Minitest::Test
  include Rack::Test::Methods

  def setup
    @config = fresh_config(compiler: :ruby)
  end

  def inner
    ->(env) { [200, { 'content-type' => 'text/plain' }, ["fallthrough #{env['PATH_INFO']}"]] }
  end

  def app
    @app ||= VueLive::Middleware.new(inner, config: @config)
  end

  def test_serves_compiled_component_with_both_url_forms
    get '/vue/App.vue'
    assert_equal 200, last_response.status
    assert_equal 'text/javascript; charset=utf-8', last_response.headers['content-type']
    assert_equal 'ruby', last_response.headers['x-vue-live']
    assert_includes last_response.body, '__sfc__.template'
    assert_match(%r{from './nested/Child\.vue\.js\?v=[0-9a-f]{16}'}, last_response.body)
    body = last_response.body
    get '/vue/App.vue.js'
    assert_equal body, last_response.body
    assert_equal body.bytesize.to_s, last_response.headers['content-length']
  end

  def test_etag_revalidation
    get '/vue/App.vue'
    etag = last_response.headers['etag']
    assert_match(/\A"[0-9a-f]{16}"\z/, etag)
    assert_equal 'no-cache', last_response.headers['cache-control']
    get '/vue/App.vue', {}, 'HTTP_IF_NONE_MATCH' => etag
    assert_equal 304, last_response.status
    assert_empty last_response.body
  end

  def test_digested_urls_are_immutable_in_production
    @config.env = 'production'
    get '/vue/App.vue'
    digest = last_response.headers['etag'].delete('"')
    get "/vue/App.vue.js?v=#{digest}"
    assert_equal 'public, max-age=31536000, immutable', last_response.headers['cache-control']
    get '/vue/App.vue.js?v=wrong'
    assert_equal 'no-cache', last_response.headers['cache-control']
  end

  def test_digested_urls_still_revalidate_while_reloading
    get '/vue/App.vue'
    digest = last_response.headers['etag'].delete('"')
    get "/vue/App.vue?v=#{digest}"
    assert_equal 'no-cache', last_response.headers['cache-control']
  end

  def test_serves_sibling_assets
    get '/vue/shared/util.js'
    assert_equal 200, last_response.status
    assert_equal 'text/javascript; charset=utf-8', last_response.headers['content-type']
    assert_includes last_response.body, 'export function shout'
    assert last_response.headers['last-modified']
  end

  def test_head_requests
    head '/vue/App.vue'
    assert_equal 200, last_response.status
    assert_empty last_response.body
    assert_equal 'text/javascript; charset=utf-8', last_response.headers['content-type']
    assert last_response.headers['etag']
  end

  def test_passes_through_everything_else
    get '/assets/application.js'
    assert_equal 'fallthrough /assets/application.js', last_response.body
    get '/vue'
    assert_equal 'fallthrough /vue', last_response.body
    get '/vuex/App.vue'
    assert_equal 'fallthrough /vuex/App.vue', last_response.body
    get '/vue/Missing.vue'
    assert_equal 'fallthrough /vue/Missing.vue', last_response.body
    get '/vue/secret.txt'
    assert_equal 'fallthrough /vue/secret.txt', last_response.body
    get '/vue/../test_helper.rb'
    refute_includes last_response.body, 'minitest'
  end

  def test_rejects_other_methods
    post '/vue/App.vue'
    assert_equal 405, last_response.status
  end

  def test_compile_error_in_development_is_a_throwing_module
    get '/vue/Broken.vue'
    assert_equal 200, last_response.status
    assert_equal 'no-store', last_response.headers['cache-control']
    assert_includes last_response.body, 'throw new Error'
    assert_includes last_response.body, 'unterminated <template>'
  end

  def test_compile_error_in_production_is_500
    @config.env = 'production'
    get '/vue/Broken.vue'
    assert_equal 500, last_response.status
    refute_includes last_response.body, 'unterminated'
  end

  def test_unsupported_feature_without_node_is_reported
    @config.compiler = :ruby
    get '/vue/Setup.vue'
    assert_includes last_response.body, '<script setup>'
  end

  def test_custom_prefix_via_options
    with_global_config(compiler: :ruby) do
      mw = VueLive::Middleware.new(inner, prefix: '/components')
      status, headers, = mw.call(Rack::MockRequest.env_for('/components/App.vue'))
      assert_equal 200, status
      assert_equal 'text/javascript; charset=utf-8', headers['content-type']
      status, = mw.call(Rack::MockRequest.env_for('/vue/App.vue'))
      assert_equal 200, status # falls through to inner app
    end
  end

  def test_local_vue_is_served_when_present
    with_tmp_app do |dir|
      FileUtils.mkdir_p(File.join(dir, 'vendor/vue_live'))
      File.write(File.join(dir, 'vendor/vue_live/vue.esm-browser.js'), 'export const version = "local"')
      cfg = fresh_config(root: dir)
      mw = VueLive::Middleware.new(inner, config: cfg)
      assert_equal '/vue/-/vue.esm-browser.js', cfg.resolved_vue_url
      status, headers, body = mw.call(Rack::MockRequest.env_for('/vue/-/vue.esm-browser.js'))
      assert_equal 200, status
      assert_equal 'text/javascript; charset=utf-8', headers['content-type']
      assert_equal ['export const version = "local"'], body
    end
  end

  def test_vendor_path_falls_through_without_local_vue
    get '/vue/-/vue.esm-browser.js'
    assert_equal 'fallthrough /vue/-/vue.esm-browser.js', last_response.body
  end

  def test_live_reload_client_and_stream_when_enabled
    @config.live_reload = true
    get '/vue/-/reload.js'
    assert_equal 200, last_response.status
    assert_equal 'text/javascript; charset=utf-8', last_response.headers['content-type']
    assert_includes last_response.body, 'EventSource'

    status, headers, body = app.call(Rack::MockRequest.env_for('/vue/-/events'))
    assert_equal 200, status
    assert_equal 'text/event-stream; charset=utf-8', headers['content-type']
    assert_kind_of VueLive::LiveReload::Frames, body
  end

  def test_live_reload_endpoints_fall_through_when_disabled
    @config.live_reload = false
    get '/vue/-/reload.js'
    assert_equal 'fallthrough /vue/-/reload.js', last_response.body
    get '/vue/-/events'
    assert_equal 'fallthrough /vue/-/events', last_response.body
  end

  def test_source_map_only_outside_production
    get '/vue/App.vue'
    assert_includes last_response.body, '//# sourceMappingURL=data:application/json'
    @config.env = 'production'
    get '/vue/App.vue'
    refute_includes last_response.body, 'sourceMappingURL'
  end
end
