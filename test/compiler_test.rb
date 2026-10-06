# frozen_string_literal: true

require_relative 'test_helper'

class CompilerTest < Minitest::Test
  def setup
    @config = fresh_config(compiler: :ruby)
  end

  def compile(src, path = 'X.vue')
    VueLive::Compiler.compile(src, relative_path: path, config: @config)
  end

  def test_full_component
    r = compile(<<~V)
      <template>
        <p class="a">{{ msg }}</p>
      </template>
      <script>
      import Other from './Other.vue'
      export default { components: { Other }, data() { return { msg: 'hi' } } }
      </script>
      <style scoped>.a { color: red }</style>
      <style>body { margin: 0 }</style>
    V
    assert_equal :ruby, r.backend
    assert_includes r.code, "import Other from './Other.vue'"
    assert_includes r.code, 'const __sfc__ = { components: { Other }, data() { return { msg: \'hi\' } } }'
    assert_includes r.code, '__sfc__.template = "<p class=\"a\">{{ msg }}<\/p>"'
    assert_includes r.code, '__sfc__.__scopeId = "data-v-'
    assert_includes r.code, '__sfc__._scopeId = "data-v-'
    assert_includes r.code, '__sfc__.__file = "X.vue"'
    assert r.code.end_with?("export default __sfc__\n")
    assert_match(/\.a\[data-v-[0-9a-f]{8}\] \{ color: red \}/, r.css)
    assert_includes r.css, 'body { margin: 0 }'
    assert_equal VueLive::Compiler.scope_id('X.vue'), r.scope_id
  end

  def test_scope_id_is_stable_and_path_based
    assert_equal VueLive::Compiler.scope_id('a/B.vue'), VueLive::Compiler.scope_id('a/B.vue')
    refute_equal VueLive::Compiler.scope_id('a/B.vue'), VueLive::Compiler.scope_id('B.vue')
    assert_match(/\Adata-v-[0-9a-f]{8}\z/, VueLive::Compiler.scope_id('x'))
  end

  def test_template_only
    r = compile('<template><p>static</p></template>')
    assert_includes r.code, 'const __sfc__ = {}'
    assert_includes r.code, '__sfc__.template = "<p>static<\/p>"'
    assert_nil r.scope_id
    refute r.css?
  end

  def test_script_only_and_define_component
    r = compile("<script>import { defineComponent } from 'vue'\nexport default defineComponent({ name: 'S' })</script>")
    assert_includes r.code, "const __sfc__ = defineComponent({ name: 'S' })"
    refute_includes r.code, '__sfc__.template'
  end

  def test_module_exports
    r = compile('<template><a/></template><script>module.exports = { name: "cjs" }</script>')
    assert_includes r.code, 'const __sfc__ = { name: "cjs" }'
  end

  def test_production_omits_file_name
    @config.env = 'production'
    r = compile('<template><a/></template>')
    refute_includes r.code, '__file'
  end

  def test_unsupported_features_raise
    e = assert_raises(VueLive::UnsupportedFeature) { compile('<template><a/></template><script setup>const a = 1</script>') }
    assert_match(/<script setup>/, e.message)
    assert_raises(VueLive::UnsupportedFeature) { compile('<template><a/></template><style lang="scss">a{}</style>') }
  end

  def test_auto_without_node_explains
    @config.compiler = :auto
    @config.node_bin = '/nonexistent/node'
    VueLive::Compiler::Node.reset!
    e = assert_raises(VueLive::UnsupportedFeature) { compile('<template><a/></template><script setup>const a = 1</script>') }
    assert_match(/vue_live node-setup/, e.message)
  end

  def test_src_attributes_resolve_siblings
    src = File.read(File.join(FIXTURES, 'app/vue/Srcs.vue'))
    r = VueLive::Compiler.compile(src, relative_path: 'Srcs.vue', absolute_path: File.join(FIXTURES, 'app/vue/Srcs.vue'),
                                       config: @config)
    assert_includes r.code, '__sfc__.template = "<em class=\"e\">{{ x }}<\/em>"'
    assert_match(/\.e\[data-v-/, r.css)
    assert_equal 2, r.dependencies.size
  end

  def test_src_outside_root_is_forbidden
    assert_raises(VueLive::ForbiddenPath) do
      VueLive::Compiler.compile('<template src="../../../etc/passwd"></template>', relative_path: 'E.vue',
                                                                                   absolute_path: File.join(FIXTURES, 'app/vue/E.vue'), config: @config)
    end
  end

  def test_ruby_backend_source_map_lines
    r = compile("<template>\n  <p/>\n</template>\n<script>\nimport x from './x.js'\nexport default { x }\n</script>")
    map = r.source_map
    assert_equal 3, map['version']
    assert_equal ['X.vue'], map['sources']
    assert_equal 'X.vue.js', map['file']
    # generated line 1 ("") is source line 4, line 2 (import) is 5, line 3 (const __sfc__) is 6
    assert_equal 'AAGA;AACA;AACA', map['mappings']
    @config.source_maps = false
    assert_nil compile('<template><a/></template><script>export default {}</script>').source_map
  end

  def test_unknown_compiler
    @config.compiler = :magic
    assert_raises(VueLive::Error) { compile('<template><a/></template>') }
  end
end
