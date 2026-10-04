# frozen_string_literal: true

require_relative 'test_helper'

class StoreTest < Minitest::Test
  def test_fetch_compiles_and_caches
    store = VueLive::Store.new(fresh_config(compiler: :ruby))
    a = store.fetch('App.vue')
    b = store.fetch('App.vue')
    assert_same a, b
    assert_equal 16, a.digest.length
    assert_equal :ruby, a.backend
    assert_includes a.code, "import Child from './nested/Child.vue.js'"
    assert_equal a, store.fetch('App.vue.js')
  end

  def test_missing_component
    store = VueLive::Store.new(fresh_config)
    assert_raises(Errno::ENOENT) { store.fetch('Nope.vue') }
    assert_nil store.digest('Nope.vue')
  end

  def test_reload_recompiles_on_change
    with_tmp_app do |dir|
      cfg = fresh_config(root: dir, reload: true, compiler: :ruby)
      store = VueLive::Store.new(cfg)
      file = File.join(dir, 'app/vue/App.vue')
      first = store.fetch('App.vue')
      File.write(file, File.read(file).sub('<h1>{{ title }}</h1>', '<h1>changed</h1>'))
      File.utime(Time.now + 5, Time.now + 5, file)
      second = store.fetch('App.vue')
      refute_equal first.digest, second.digest
      assert_includes second.code, 'changed'
    end
  end

  def test_no_reload_in_production
    with_tmp_app do |dir|
      cfg = fresh_config(root: dir, env: 'production', compiler: :ruby)
      store = VueLive::Store.new(cfg)
      file = File.join(dir, 'app/vue/App.vue')
      first = store.fetch('App.vue')
      File.write(file, File.read(file).sub('<h1>{{ title }}</h1>', '<h1>changed</h1>'))
      File.utime(Time.now + 5, Time.now + 5, file)
      assert_same first, store.fetch('App.vue')
    end
  end

  def test_file_cache_survives_new_store
    with_tmp_app do |dir|
      cfg = fresh_config(root: dir, cache: :file, cache_path: 'tmp/c', compiler: :ruby)
      one = VueLive::Store.new(cfg).fetch('App.vue')
      assert Dir.exist?(File.join(dir, 'tmp/c'))
      two = VueLive::Store.new(cfg).fetch('App.vue')
      assert_equal one.code, two.code
      assert_equal one.digest, two.digest
      VueLive::Store.new(cfg).clear
      refute Dir.exist?(File.join(dir, 'tmp/c'))
    end
  end

  def test_src_dependencies_trigger_recompile
    with_tmp_app do |dir|
      cfg = fresh_config(root: dir, reload: true, compiler: :ruby)
      store = VueLive::Store.new(cfg)
      first = store.fetch('Srcs.vue')
      dep = File.join(dir, 'app/vue/shared/srcs.html')
      File.write(dep, '<b class="e">{{ x }}</b>')
      File.utime(Time.now + 5, Time.now + 5, dep)
      assert_includes store.fetch('Srcs.vue').code, '<b class=\"e\">'
      refute_equal first.digest, store.fetch('Srcs.vue').digest
    end
  end
end
