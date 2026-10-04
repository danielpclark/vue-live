# frozen_string_literal: true

require_relative 'test_helper'

# Runs only when VUE_LIVE_NODE_ROOT points at a directory with @vue/compiler-sfc installed.
class NodeCompilerTest < Minitest::Test
  def setup
    skip 'set VUE_LIVE_NODE_ROOT to a project with @vue/compiler-sfc to run Node backend tests' unless node_available?
    @config = fresh_config(root: NODE_ROOT, compiler: :node, source_path: File.join(FIXTURES, 'app/vue'))
  end

  def test_script_setup_scss_and_render_function
    src = File.read(File.join(FIXTURES, 'app/vue/Setup.vue'))
    r = VueLive::Compiler.compile(src, relative_path: 'Setup.vue', config: @config)
    assert_equal :node, r.backend
    assert_includes r.code, 'function render('
    assert_includes r.code, '__sfc__.render = render'
    assert_includes r.code, '__isScriptSetup'
    assert_includes r.code, '__sfc__.__scopeId = "data-v-'
    assert_match(/\.setup\[data-v-[0-9a-f]{8}\] \{\s*color: rgb\(0, 0, 255\);/, r.css)
  end

  def test_typescript_is_stripped
    src = "<template><b>{{ n }}</b></template><script setup lang=\"ts\">import { ref } from 'vue'\nconst n = ref<number>(1)\ndefineProps<{ a: string }>()</script>"
    r = VueLive::Compiler.compile(src, relative_path: 'TS.vue', config: @config)
    refute_includes r.code, 'ref<number>'
    refute_includes r.code, ': any'
    assert_includes r.code, 'type: String'
  end

  def test_auto_picks_node_for_advanced_components_only
    @config.compiler = :auto
    plain = VueLive::Compiler.compile('<template><a/></template>', relative_path: 'P.vue', config: @config)
    assert_equal :ruby, plain.backend
    adv = VueLive::Compiler.compile('<template><a/></template><script setup>const x = 1</script>', relative_path: 'A.vue', config: @config)
    assert_equal :node, adv.backend
  end

  def test_errors_are_reported
    e = assert_raises(VueLive::CompileError) do
      VueLive::Compiler.compile("<template><div></span></template>", relative_path: 'Bad.vue', config: @config)
    end
    assert_match(/Bad\.vue/, e.message)
  end

  def test_css_modules
    r = VueLive::Compiler.compile('<template><p :class="$style.red">x</p></template><style module>.red{color:red}</style>', relative_path: 'M.vue', config: @config)
    assert_includes r.code, '__sfc__.__cssModules = {"$style":{"red":"'
  end
end
