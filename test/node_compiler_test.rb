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
    adv = VueLive::Compiler.compile('<template><a/></template><script setup>const x = 1</script>', relative_path: 'A.vue',
                                                                                                   config: @config)
    assert_equal :node, adv.backend
  end

  def test_errors_are_reported
    e = assert_raises(VueLive::CompileError) do
      VueLive::Compiler.compile('<template><div></span></template>', relative_path: 'Bad.vue', config: @config)
    end
    assert_match(/Bad\.vue/, e.message)
  end

  def test_worker_is_reused_and_restarts_after_dying
    VueLive::Compiler::Node.reset!
    worker = VueLive::Compiler::Node.worker_for(@config)
    first = VueLive::Compiler.compile('<template><a/></template>', relative_path: 'W1.vue', config: @config)
    assert_equal :node, first.backend
    assert worker.alive?
    pid = worker.instance_variable_get(:@pid)
    VueLive::Compiler.compile('<template><b/></template>', relative_path: 'W2.vue', config: @config)
    assert_equal pid, worker.instance_variable_get(:@pid), 'second compile must reuse the process'

    Process.kill('KILL', pid)
    sleep 0.2
    third = VueLive::Compiler.compile('<template><c/></template>', relative_path: 'W3.vue', config: @config)
    assert_includes third.code, '__sfc__.render = render'
    refute_equal pid, worker.instance_variable_get(:@pid), 'worker must be restarted'
    assert worker.alive?
  end

  def test_worker_is_much_faster_than_one_shot
    @config.node_worker = true
    VueLive::Compiler.compile('<template><a/></template>', relative_path: 'Warm.vue', config: @config) # start it
    t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    5.times { |i| VueLive::Compiler.compile("<template><a>#{i}</a></template>", relative_path: "Fast#{i}.vue", config: @config) }
    worker_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t) * 1000 / 5
    assert_operator worker_ms, :<, 150, "worker compile averaged #{worker_ms.round}ms"
  end

  def test_one_shot_mode_still_works
    @config.node_worker = false
    r = VueLive::Compiler.compile('<template><a/></template><script setup>const n = 1</script>', relative_path: 'OneShot.vue',
                                                                                                 config: @config)
    assert_equal :node, r.backend
    assert_includes r.code, '__isScriptSetup'
  end

  def test_source_map_covers_script_and_template
    src = "<template>\n  <p>{{ n }}</p>\n</template>\n<script setup lang=\"ts\">\nimport { ref } from 'vue'\nconst n = ref<number>(1)\n</script>"
    r = VueLive::Compiler.compile(src, relative_path: 'Mapped.vue', config: @config)
    map = r.source_map
    refute_nil map
    assert_equal ['Mapped.vue'], map['sources']
    assert_equal [src], map['sourcesContent']
    assert_operator map['mappings'].length, :>, 10
    @config.source_maps = false
    assert_nil VueLive::Compiler.compile(src, relative_path: 'Unmapped.vue', config: @config).source_map
  end

  def test_css_modules
    r = VueLive::Compiler.compile('<template><p :class="$style.red">x</p></template><style module>.red{color:red}</style>',
                                  relative_path: 'M.vue', config: @config)
    assert_includes r.code, '__sfc__.__cssModules = {"$style":{"red":"'
  end
end
