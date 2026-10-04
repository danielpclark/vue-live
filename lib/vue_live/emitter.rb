# frozen_string_literal: true

require 'json'
require 'digest'

module VueLive
  # Finishes a Compiler::Result into the JavaScript the browser receives:
  #
  #   * relative imports of `./Foo.vue` become `./Foo.vue.js` so the same output works from the
  #     live middleware and from a precompiled directory served by any static file server
  #     (a block can further rewrite each relative specifier, e.g. to add `?v=<digest>`)
  #   * <style> content is injected once per component via a constructable stylesheet
  #     (CSP-friendly), falling back to a <style> element
  #   * the source map, when present, is appended inline
  #
  # The component code always starts on line 1 so source maps need no offset.
  module Emitter
    # Any relative/absolute-path import specifier:
    #   import X from './x.vue'   import './x.js'   export * from '../y.vue'   import('./z.vue')
    RELATIVE_IMPORT = %r{((?:\bfrom\s*|\bimport\s*\(?\s*|\bexport\s+\*\s+from\s*)\s*)(['"])((?:\.{1,2}/|/)[^'"?#]+)([?#][^'"]*)?\2} # rubocop:disable Layout/LineLength

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

    # +rewrite+ receives each relative specifier (already `.vue` -> `.vue.js`) and returns the
    # specifier to emit; nil keeps it.
    def emit(result, relative_path:, inject_styles: true, banner: true, source_map: true, &rewrite)
      out = rewrite_imports(result.code, &rewrite)
      out << "\n" unless out.end_with?("\n")
      out << "// #{relative_path} — compiled by vue_live (#{result.backend})\n" if banner
      if inject_styles && result.css?
        key = "vue-live-#{Digest::SHA256.hexdigest(relative_path)[0, 10]}"
        out << format(STYLE_RUNTIME, css: js_string(result.css), key: js_string(key))
      end
      out << SourceMap.inline_comment(result.source_map) if source_map && result.source_map && !result.source_map.empty?
      out
    end

    def rewrite_imports(code)
      code.gsub(RELATIVE_IMPORT) do
        prefix, quote, spec, suffix = Regexp.last_match[1..4]
        spec = "#{spec}.js" if spec.end_with?('.vue')
        spec = (block_given? && yield(spec)) || spec unless suffix # leave explicit queries alone
        "#{prefix}#{quote}#{spec}#{suffix}#{quote}"
      end
    end

    def js_string(str)
      JSON.generate(str).gsub(' ', ' ').gsub(' ', ' ').gsub('</', '<\/')
    end
  end
end
