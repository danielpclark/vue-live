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
    child = store.fetch('nested/Child.vue')
    assert_includes a.code, "import Child from './nested/Child.vue.js?v=#{child.digest}'"
    assert_includes a.code, "import { shout } from './shared/util.js?v=#{store.file_digest('shared/util.js')}'"
    assert_includes a.dependencies, File.join(FIXTURES, 'app/vue/nested/Child.vue')
    assert_equal a, store.fetch('App.vue.js')
  end

  def test_digest_imports_can_be_disabled
    store = VueLive::Store.new(fresh_config(compiler: :ruby, digest_imports: false))
    assert_includes store.fetch('App.vue').code, "import Child from './nested/Child.vue.js'\n"
  end

  def test_parent_digest_follows_child_changes
    with_tmp_app do |dir|
      store = VueLive::Store.new(fresh_config(root: dir, reload: true, compiler: :ruby))
      before = store.fetch('App.vue')
      child = File.join(dir, 'app/vue/nested/Child.vue')
      File.write(child, File.read(child).sub('n = {{ n }}', 'n: {{ n }}'))
      File.utime(Time.now + 5, Time.now + 5, child)
      after = store.fetch('App.vue')
      refute_equal before.digest, after.digest, 'a changed child must change the parent URL set'
      assert_includes after.code, "?v=#{store.fetch('nested/Child.vue').digest}'"
    end
  end

  def test_import_cycles_do_not_recurse_forever
    with_tmp_app do |dir|
      File.write(File.join(dir, 'app/vue/CycleA.vue'),
                 "<template><b/></template><script>import B from './CycleB.vue'\nexport default { components: { B } }</script>")
      File.write(File.join(dir, 'app/vue/CycleB.vue'),
                 "<template><a/></template><script>import A from './CycleA.vue'\nexport default { components: { A } }</script>")
      store = VueLive::Store.new(fresh_config(root: dir, compiler: :ruby))
      a = store.fetch('CycleA.vue')
      b = store.fetch('CycleB.vue')
      assert_match(%r{from './CycleB\.vue\.js\?v=[0-9a-f]{16}'}, a.code)
      assert_includes b.code, "from './CycleA.vue.js'" # the back edge stays undigested
    end
  end

  def test_unresolvable_imports_are_left_alone
    with_tmp_app do |dir|
      File.write(File.join(dir, 'app/vue/Loose.vue'),
                 "<template><b/></template><script>import X from './missing.js'\nimport Y from './Nope.vue'\nimport Z from '/elsewhere/Z.vue'\nimport W from './shared/util.js?raw'\nexport default {}</script>")
      store = VueLive::Store.new(fresh_config(root: dir, compiler: :ruby))
      code = store.fetch('Loose.vue').code
      assert_includes code, "from './missing.js'"
      assert_includes code, "from './Nope.vue.js'"
      assert_includes code, "from '/elsewhere/Z.vue.js'"
      assert_includes code, "from './shared/util.js?raw'"
    end
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
