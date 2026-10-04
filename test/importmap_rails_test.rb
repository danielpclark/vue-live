# frozen_string_literal: true

require_relative 'test_helper'
require 'open3'

# importmap-rails and a second Rails application cannot share a process with railtie_test.rb, so
# this scenario boots in a child Ruby process.
class ImportmapRailsTest < Minitest::Test
  SCRIPT = <<~RUBY
    ENV['RAILS_ENV'] = 'test'
    $LOAD_PATH.unshift '#{File.expand_path('../lib', __dir__)}'
    require 'rails'
    require 'action_controller/railtie'
    require 'action_view/railtie'
    require 'importmap-rails'
    require 'vue_live/railtie'

    class ImportmapApp < Rails::Application
      config.root = '#{FIXTURES}'
      config.eager_load = false
      config.logger = Logger.new(File::NULL)
      config.secret_key_base = 'x' * 64
      config.vue_live.compiler = :ruby
    end
    ImportmapApp.initialize!

    view = ActionView::Base.with_empty_template_cache.with_view_paths([], {}, nil)
    puts "pinned: " + ImportmapApp.importmap.packages.key?('vue').to_s
    puts "pin to: " + ImportmapApp.importmap.packages['vue'].path
    puts "tag: [" + view.vue_live_import_map_tag.to_s + "]"
    puts "json: " + ImportmapApp.importmap.to_json(resolver: view)
  RUBY

  def test_vue_is_pinned_and_import_map_tag_defers
    skip 'importmap-rails not installed' unless Gem::Specification.find_all_by_name('importmap-rails').any?
    out, err, status = Open3.capture3(RbConfig.ruby, '-e', SCRIPT)
    assert status.success?, err
    assert_includes out, 'pinned: true'
    assert_includes out, 'pin to: https://cdn.jsdelivr.net/npm/vue@'
    assert_includes out, 'tag: []'
    assert_match(/"vue": "https:\/\/cdn\.jsdelivr\.net\/npm\/vue@[\d.]+\/dist\/vue\.esm-browser\.js"/, out)
  end
end
