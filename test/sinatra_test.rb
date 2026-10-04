# frozen_string_literal: true

require_relative 'test_helper'
require 'rack/test'
require 'sinatra/base'
require 'vue_live/sinatra'

class SinatraTest < Minitest::Test
  include Rack::Test::Methods

  def app
    @previous_config = VueLive.config
    VueLive.config = fresh_config(compiler: :ruby)
    Class.new(Sinatra::Base) do
      set :root, FIXTURES
      set :environment, :test
      set :vue_live, prefix: '/vue'
      register VueLive::Sinatra
      get('/') { "<!doctype html>#{vue_live_import_map_tag}#{vue_live_mount_tag('App.vue', '#app', element: true)}" }
    end
  end

  def teardown
    VueLive.config = @previous_config if @previous_config
  end

  def test_component_is_served_and_helpers_available
    get '/'
    assert_equal 200, last_response.status
    assert_includes last_response.body, '<script type="importmap">'
    assert_match(%r{import App from "/vue/App\.vue\.js\?v=[0-9a-f]+"}, last_response.body)
    assert_equal FIXTURES, VueLive.config.root

    get '/vue/App.vue.js'
    assert_equal 200, last_response.status
    assert_equal 'text/javascript; charset=utf-8', last_response.headers['content-type']
    assert_includes last_response.body, '__sfc__.template'
  end

  def test_unrelated_routes_untouched
    get '/nope'
    assert_equal 404, last_response.status
  end
end
