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
    result = VueLive::Compiler::Result.new(code: "const __sfc__ = {}\nexport default __sfc__\n", css: ".a { x: y }", backend: :ruby, dependencies: [])
    out = VueLive::Emitter.emit(result, relative_path: 'A.vue')
    assert out.start_with?('// A.vue — compiled by vue_live (ruby)')
    assert_includes out, 'CSSStyleSheet'
    assert_includes out, '})(".a { x: y }", "vue-live-'
    plain = VueLive::Emitter.emit(result, relative_path: 'A.vue', inject_styles: false)
    refute_includes plain, 'CSSStyleSheet'
  end

  def test_no_style_block_when_css_empty
    result = VueLive::Compiler::Result.new(code: 'export default {}', css: "  \n", backend: :ruby, dependencies: [])
    refute_includes VueLive::Emitter.emit(result, relative_path: 'A.vue'), 'CSSStyleSheet'
  end

  def test_js_string_escapes_script_terminators
    assert_equal '"<\/script><\/p> "', VueLive::Emitter.js_string("</script></p> ")
  end
end
