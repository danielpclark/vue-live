# frozen_string_literal: true

require_relative 'test_helper'

class EmitterTest < Minitest::Test
  def test_rewrites_relative_vue_imports_only
    code = <<~JS
      import A from './A.vue'
      import B from "../x/B.vue"
      import '/abs/C.vue'
      import vue from 'vue'
      import D from 'some-package/D.vue'
      export * from './E.vue'
      const F = () => import('./F.vue')
      const G = import("./G.vue")
    JS
    out = VueLive::Emitter.rewrite_imports(code)
    assert_includes out, "import A from './A.vue.js'"
    assert_includes out, 'import B from "../x/B.vue.js"'
    assert_includes out, "import '/abs/C.vue.js'"
    assert_includes out, "import vue from 'vue'"
    assert_includes out, "import D from 'some-package/D.vue'"
    assert_includes out, "export * from './E.vue.js'"
    assert_includes out, "import('./F.vue.js')"
    assert_includes out, 'import("./G.vue.js")'
  end

  def test_style_injection
    result = VueLive::Compiler::Result.new(code: "const __sfc__ = {}\nexport default __sfc__\n", css: '.a { x: y }',
                                           backend: :ruby, dependencies: [])
    out = VueLive::Emitter.emit(result, relative_path: 'A.vue')
    assert out.start_with?("const __sfc__ = {}\n"), 'component code must start on line 1 for source maps'
    assert_includes out, '// A.vue — compiled by vue_live (ruby)'
    assert_includes out, 'CSSStyleSheet'
    assert_includes out, '})(".a { x: y }", "vue-live-'
    plain = VueLive::Emitter.emit(result, relative_path: 'A.vue', inject_styles: false)
    refute_includes plain, 'CSSStyleSheet'
  end

  def test_no_style_block_when_css_empty
    result = VueLive::Compiler::Result.new(code: 'export default {}', css: "  \n", backend: :ruby, dependencies: [])
    refute_includes VueLive::Emitter.emit(result, relative_path: 'A.vue'), 'CSSStyleSheet'
  end

  def test_rewrite_block_receives_relative_specifiers
    code = "import A from './A.vue'\nimport B from './b.js'\nimport C from '/abs/C.vue'\nimport D from 'pkg'\nimport E from './e.js?x=1'"
    seen = []
    out = VueLive::Emitter.rewrite_imports(code) do |spec|
      seen << spec
      "#{spec}?v=1"
    end
    assert_equal ['./A.vue.js', './b.js', '/abs/C.vue.js'], seen
    assert_includes out, "from './A.vue.js?v=1'"
    assert_includes out, "from './b.js?v=1'"
    assert_includes out, "from 'pkg'"
    assert_includes out, "from './e.js?x=1'"
  end

  def test_inline_source_map
    map = VueLive::SourceMap.new('A.vue', 'src').add(generated_line: 1, original_line: 3).to_h
    result = VueLive::Compiler::Result.new(code: 'export default {}', css: '', source_map: map, backend: :ruby, dependencies: [])
    out = VueLive::Emitter.emit(result, relative_path: 'A.vue')
    assert_match(%r{//# sourceMappingURL=data:application/json;charset=utf-8;base64,[A-Za-z0-9+/=]+\n\z}, out)
    refute_includes VueLive::Emitter.emit(result, relative_path: 'A.vue', source_map: false), 'sourceMappingURL'
  end

  def test_js_string_escapes_script_terminators
    assert_equal '"<\/script><\/p> "', VueLive::Emitter.js_string('</script></p> ')
  end
end
