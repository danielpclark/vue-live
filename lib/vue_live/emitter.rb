# frozen_string_literal: true

require 'json'
require 'digest'

module VueLive
  # Finishes a Compiler::Result into the JavaScript the browser receives:
  #
  #   * relative imports of `./Foo.vue` become `./Foo.vue.js` so the same output works from the
  #     live middleware and from a precompiled directory served by any static file server
  #   * <style> content is injected once per component via a constructable stylesheet
  #     (CSP-friendly), falling back to a <style> element
  module Emitter
    # `import X from './x.vue'`, `import './x.vue'`, `export * from './x.vue'`, `import('./x.vue')`
    VUE_IMPORT = /((?:\bfrom\s*|\bimport\s*\(?\s*|\bexport\s+\*\s+from\s*)\s*)(['"])((?:\.{1,2}\/|\/)[^'"]+?\.vue)\2/

    STYLE_RUNTIME = <<~JS
      ;(function (css, key) {
        if (typeof document === 'undefined') return
        var registry = (globalThis.__vueLiveStyles = globalThis.__vueLiveStyles || {})
        if (registry[key]) return
        registry[key] = true
        try {
          if (document.adoptedStyleSheets && typeof CSSStyleSheet === 'function') {
            var sheet = new CSSStyleSheet()
            sheet.replaceSync(css)
            document.adoptedStyleSheets = document.adoptedStyleSheets.concat(sheet)
            return
          }
        } catch (e) { /* fall through to a <style> element */ }
        var el = document.createElement('style')
        el.setAttribute('data-vue-live', key)
        el.textContent = css
        document.head.appendChild(el)
      })(%<css>s, %<key>s)
    JS

    module_function

    def emit(result, relative_path:, inject_styles: true, banner: true)
      code = rewrite_imports(result.code)
      out = +''
      out << "// #{relative_path} — compiled by vue_live (#{result.backend})\n" if banner
      out << code
      out << "\n" unless out.end_with?("\n")
      if inject_styles && result.css?
        key = "vue-live-#{Digest::SHA256.hexdigest(relative_path)[0, 10]}"
        out << format(STYLE_RUNTIME, css: js_string(result.css), key: js_string(key))
      end
      out
    end

    def rewrite_imports(code)
      code.gsub(VUE_IMPORT) { "#{Regexp.last_match(1)}#{Regexp.last_match(2)}#{Regexp.last_match(3)}.js#{Regexp.last_match(2)}" }
    end

    def js_string(str)
      JSON.generate(str).gsub(" ", ' ').gsub(" ", ' ').gsub('</', '<\/')
    end
  end
end
