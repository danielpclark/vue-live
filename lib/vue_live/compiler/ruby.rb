# frozen_string_literal: true

require 'json'
require_relative '../scoped_css'

module VueLive
  module Compiler
    # The zero-dependency backend.
    #
    # Output for a component with <template>, <script> and <style scoped>:
    #
    #   import Something from './Something.vue'   // the user's own script, untouched
    #   const __sfc__ = { components: { Something }, data() { ... } }
    #   __sfc__.template = "<div class=\"a\">…</div>"
    #   __sfc__.__scopeId = "data-v-1a2b3c4d"     // Vue 3 applies this in the renderer
    #   __sfc__._scopeId  = "data-v-1a2b3c4d"     // same for Vue 2
    #   export default __sfc__
    #
    # The template string is compiled in the browser by Vue's *full* build, which is what the
    # old Sprockets .vue setups relied on too.  Scope ids are applied by Vue's renderer, not its
    # template compiler, so scoped styles work without a build step.
    class Ruby < Base
      EXPORT_DEFAULT = /^[ \t]*export[ \t]+default[ \t]+/m
      MODULE_EXPORTS = /^[ \t]*module\.exports[ \t]*=[ \t]*/m

      def compile(descriptor, relative_path:, absolute_path: nil)
        unless descriptor.advanced_features.empty?
          raise UnsupportedFeature.new(
            "uses #{descriptor.advanced_features.join(', ')}; the Ruby compiler supports plain " \
            '<template>, <script> and <style> blocks only (switch to the :node compiler for more)',
            file: relative_path
          )
        end

        dependencies = []
        scope_id = Compiler.scope_id(relative_path)
        scoped = descriptor.scoped_styles?

        script, script_file = block_source(descriptor.script, absolute_path, dependencies)
        code = rewrite_script(script.to_s, relative_path)
        map = build_map(descriptor, script.to_s, code, script_file.nil?) if config.source_maps?

        if descriptor.template
          template, = block_source(descriptor.template, absolute_path, dependencies)
          code << "__sfc__.template = #{js_string(template.strip)}\n"
        end

        if scoped
          code << "__sfc__.__scopeId = #{js_string(scope_id)}\n"
          code << "__sfc__._scopeId = #{js_string(scope_id)}\n"
        end
        code << "__sfc__.__file = #{js_string(relative_path)}\n" unless config.production?
        code << "export default __sfc__\n"

        css = descriptor.styles.map do |style|
          content, = block_source(style, absolute_path, dependencies)
          style.scoped? ? ScopedCSS.rewrite(content, scope_id) : content
        end.join("\n")

        Result.new(code: code, css: css, source_map: map&.to_h, scope_id: scoped ? scope_id : nil, backend: :ruby,
                   dependencies: dependencies)
      end

      private

      # `export default {...}` becomes `const __sfc__ = {...}` so we can decorate the options
      # object before re-exporting it.  Works for `export default defineComponent({...})` too.
      def rewrite_script(script, relative_path)
        body = script.dup
        if body.match?(EXPORT_DEFAULT)
          body.sub!(EXPORT_DEFAULT, 'const __sfc__ = ')
        elsif body.match?(MODULE_EXPORTS)
          body.sub!(MODULE_EXPORTS, 'const __sfc__ = ')
        else
          body << "\nconst __sfc__ = {}"
        end
        if body.match?(EXPORT_DEFAULT)
          raise CompileError.new('only one `export default` is allowed in <script>', file: relative_path)
        end

        "#{body.rstrip}\n"
      end

      # The script block is copied line for line (only `export default` is rewritten in place), so
      # each generated line of it maps straight to its line in the .vue file.
      def build_map(descriptor, script, code, inline_script)
        map = SourceMap.new(descriptor.filename, descriptor.source)
        return map unless descriptor.script && inline_script && !script.empty?

        # Block content starts right after the opening tag, so its first line is the tag's line.
        script_lines = script.rstrip.split("\n", -1).length # the trailing newline is not a line
        generated_lines = code.split("\n", -1).length
        map.add_block(generated_line: 1, original_line: descriptor.script.line, count: [script_lines, generated_lines].min)
        map
      end

      def js_string(str)
        # JSON is a subset of JS string literal syntax; escape the two JS-only line terminators and
        # "</script>" so the output is safe even when inlined into HTML.
        JSON.generate(str).gsub(' ', ' ').gsub(' ', ' ').gsub('</', '<\/')
      end
    end
  end
end
