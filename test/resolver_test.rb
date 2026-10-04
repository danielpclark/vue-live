# frozen_string_literal: true

require_relative 'test_helper'

class ResolverTest < Minitest::Test
  def setup
    @r = VueLive::Resolver.new(fresh_config)
  end

  def test_resolves_components_and_assets
    t = @r.resolve('App.vue')
    assert t.vue?
    assert_equal 'App.vue', t.relative_path
    assert_equal 'nested/Child.vue', @r.resolve('nested/Child.vue.js').relative_path
    assert_equal 'shared/util.js', @r.resolve('shared/util.js').relative_path
    refute @r.resolve('shared/util.js').vue?
  end

  def test_rejects_traversal_hidden_and_unknown_extensions
    assert_nil @r.resolve('../test_helper.rb')
    assert_nil @r.resolve('..%2F..%2Fetc/passwd')
    assert_nil @r.resolve('shared/../../fixtures/app/vue/App.vue')
    assert_nil @r.resolve('.hidden.vue')
    assert_nil @r.resolve('secret.txt')
    assert_nil @r.resolve('App.vue%00.js')
    assert_nil @r.resolve('')
    assert_nil @r.resolve('nested')
  end

  def test_listings
    assert_includes @r.components, 'App.vue'
    assert_includes @r.components, 'nested/Child.vue'
    refute_includes @r.files, 'secret.txt'
    assert_includes @r.files, 'shared/util.js'
  end
end
