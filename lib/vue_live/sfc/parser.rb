# frozen_string_literal: true

require_relative 'descriptor'

module VueLive
  module SFC
    # Splits a .vue file into its top-level blocks.
    #
    # Only the top level is parsed; the contents of <template> are handed to Vue's own compiler
    # untouched, so nested <template v-slot> elements, comments and so on survive as-is.
    class Parser
      BLOCK_START = %r{<(template|script|style|[a-zA-Z][\w-]*)(\s[^>]*?)?(/?)>}m
      ATTR        = %r{([^\s=/"']+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?}

      def self.parse(source, filename: 'anonymous.vue')
        new(source, filename).parse
      end

      def initialize(source, filename)
        @source = source
        @filename = filename
      end

      def parse
        template = nil
        script = nil
        script_setup = nil
        styles = []
        custom = []

        pos = 0
        while (m = BLOCK_START.match(@source, pos))
          tag        = m[1]
          attrs      = parse_attrs(m[2].to_s)
          self_close = m[3] == '/'
          start      = m.end(0)
          line       = @source[0...m.begin(0)].count("\n") + 1

          if self_close
            content = ''
            pos = start
          else
            close = find_close(tag, start)
            raise CompileError.new("unterminated <#{tag}> block starting on line #{line}", file: @filename) unless close

            content = @source[start...close[0]]
            pos = close[1]
          end

          block = Block.new(type: tag, content: content, attrs: attrs, line: line)
          case tag
          when 'template'
            raise CompileError.new('only one top-level <template> block is allowed', file: @filename) if template

            template = block
          when 'script'
            if block.setup?
              raise CompileError.new('only one <script setup> block is allowed', file: @filename) if script_setup

              script_setup = block
            else
              raise CompileError.new('only one plain <script> block is allowed', file: @filename) if script

              script = block
            end
          when 'style'
            styles << block
          else
            custom << block
          end
        end

        if template.nil? && script.nil? && script_setup.nil?
          raise CompileError.new('at least a <template> or <script> block is required', file: @filename)
        end

        Descriptor.new(filename: @filename, source: @source, template: template, script: script,
                       script_setup: script_setup, styles: styles, custom_blocks: custom)
      end

      private

      # Returns [content_end, after_close_tag] for the block opened at +start+.
      def find_close(tag, start)
        if tag == 'template'
          # Templates nest (<template v-slot>), so balance open/close tags.
          depth = 1
          scan = start
          re = %r{<(/?)template(?=[\s>/])[^>]*?(/?)>}m
          while (m = re.match(@source, scan))
            if m[1] == '/'
              depth -= 1
              return [m.begin(0), m.end(0)] if depth.zero?
            elsif m[2] != '/'
              depth += 1
            end
            scan = m.end(0)
          end
          nil
        else
          idx = @source.index(%r{</#{Regexp.escape(tag)}\s*>}i, start)
          return nil unless idx

          close_end = @source.index('>', idx) + 1
          [idx, close_end]
        end
      end

      def parse_attrs(str)
        attrs = {}
        str.scan(ATTR) do |name, dq, sq, bare|
          attrs[name] = dq || sq || bare || ''
        end
        attrs
      end
    end
  end
end
