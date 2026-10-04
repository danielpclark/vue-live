# frozen_string_literal: true

# Serves the fixture components plus a page that mounts them, for test/e2e/e2e_test.rb.
#   ruby test/e2e/server.rb <node-project-root> <port>
$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'vue_live'
require 'rackup'
require 'webrick'
require 'rackup/handler/webrick'

node_root, port = ARGV
VueLive.configure do |c|
  c.root = node_root || Dir.pwd
  c.source_path = File.expand_path('../fixtures/app/vue', __dir__)
  c.compiler = :auto
  c.logger = Logger.new($stderr)
end

class Page
  include VueLive::Helpers

  def html
    <<~HTML
      <!doctype html><html><head><meta charset="utf-8">#{vue_live_import_map_tag}</head>
      <body>
        #{vue_live_mount_tag('App.vue', '#app', props: { title: 'E2E' }, element: true)}
        <div id="setup"></div>
        #{vue_live_module_tag("import { createApp } from 'vue'\nimport S from '#{vue_live_path('Setup.vue')}'\ncreateApp(S).mount('#setup')")}
        <div id="outside" class="child">outside</div>
      </body></html>
    HTML
  end
end

app = Rack::Builder.new do
  use VueLive::Middleware
  run ->(env) { env['PATH_INFO'] == '/' ? [200, { 'content-type' => 'text/html' }, [Page.new.html]] : [404, {}, ['not found']] }
end

Rackup::Handler::WEBrick.run(app, Port: (port || 9393).to_i, Host: '127.0.0.1', AccessLog: [], Logger: WEBrick::Log.new(File::NULL))
