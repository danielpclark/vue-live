# frozen_string_literal: true

module VueLive
  # Rewrites the selectors of a <style scoped> block so they only match elements carrying the
  # component's scope attribute, exactly like @vue/compiler-sfc does:
  #
  #   .a .b          -> .a .b[data-v-xxx]
  #   .a :deep(.b)   -> .a[data-v-xxx] .b
  #   .a ::v-deep .b -> .a[data-v-xxx] .b
  #   :slotted(.a)   -> .a[data-v-xxx-s]
  #   :global(.a)    -> .a
  #   @keyframes     -> names left alone (animations are not scoped)
  #
  # The implementation is a small, forgiving CSS walker; it does not validate the stylesheet.
  class ScopedCSS
    def self.rewrite(css, scope_id)
      new(scope_id).rewrite(css)
    end

    def initialize(scope_id)
      @attr = "[#{scope_id}]"
      @slot_attr = "[#{scope_id}-s]"
    end

    def rewrite(css)
      out = +''
      process(strip_comments(css), out, scope: true)
      out
    end

    private

    def strip_comments(css)
      css.gsub(%r{/\*.*?\*/}m, '')
    end

    # Walk a stylesheet (or the body of a conditional at-rule) and append the rewritten text.
    def process(css, out, scope:)
      i = 0
      len = css.length
      while i < len
        # whitespace between rules
        if css[i] =~ /\s/
          out << css[i]
          i += 1
          next
        end

        brace = find_rule_boundary(css, i)
        if brace.nil?
          out << css[i..]
          break
        end

        kind, open_idx = brace
        head = css[i...open_idx]

        if kind == :statement # e.g. @import ...;  @charset ...;
          out << head << ';'
          i = open_idx + 1
          next
        end

        close_idx = matching_brace(css, open_idx)
        body = css[(open_idx + 1)...close_idx]

        if head.lstrip.start_with?('@')
          name = head.strip[/\A@([\w-]+)/, 1].to_s.downcase
          out << head << '{'
          if %w[media supports layer container document].include?(name)
            process(body, out, scope: scope)
          else
            # @keyframes, @font-face, @page, @property ... : copy verbatim
            out << body
          end
          out << '}'
        else
          out << (scope ? rewrite_selector_list(head) : head) << '{' << body << '}'
        end
        i = close_idx + 1
      end
    end

    # From +i+ find whether the next rule is a block ({) or a statement (;).  Returns
    # [:block, index_of_brace] or [:statement, index_of_semicolon], ignoring quoted strings.
    def find_rule_boundary(css, i)
      quote = nil
      depth = 0
      while i < css.length
        c = css[i]
        if quote
          quote = nil if c == quote && css[i - 1] != '\\'
        elsif c == '"' || c == "'"
          quote = c
        elsif c == '('
          depth += 1
        elsif c == ')'
          depth -= 1
        elsif depth.zero? && c == '{'
          return [:block, i]
        elsif depth.zero? && c == ';'
          return [:statement, i]
        end
        i += 1
      end
      nil
    end

    def matching_brace(css, open_idx)
      depth = 0
      quote = nil
      i = open_idx
      while i < css.length
        c = css[i]
        if quote
          quote = nil if c == quote && css[i - 1] != '\\'
        elsif c == '"' || c == "'"
          quote = c
        elsif c == '{'
          depth += 1
        elsif c == '}'
          depth -= 1
          return i if depth.zero?
        end
        i += 1
      end
      css.length
    end

    def rewrite_selector_list(list)
      leading = list[/\A\s*/]
      trailing = list[/\s*\z/]
      selectors = split_top_level(list.strip, ',')
      leading + selectors.map { |s| rewrite_selector(s.strip) }.join(', ') + trailing
    end

    # Split on +sep+ while respecting parentheses and quotes.
    def split_top_level(str, sep)
      parts = []
      depth = 0
      quote = nil
      buf = +''
      str.each_char.with_index do |c, idx|
        if quote
          quote = nil if c == quote && str[idx - 1] != '\\'
          buf << c
        elsif c == '"' || c == "'"
          quote = c
          buf << c
        elsif c == '('
          depth += 1
          buf << c
        elsif c == ')'
          depth -= 1
          buf << c
        elsif c == sep && depth.zero?
          parts << buf
          buf = +''
        else
          buf << c
        end
      end
      parts << buf
      parts
    end

    def rewrite_selector(sel)
      return sel if sel.empty?

      # :global(...) escapes scoping entirely.
      if (m = sel.match(/\A:global\((.*)\)\z/m))
        return m[1].strip
      end

      # :deep(x) / ::v-deep x / >>> x / /deep/ x : scope the part *before*, leave the rest alone.
      if (m = sel.match(/\A(.*?)(?:\s*::v-deep\((.*?)\)|\s*:deep\((.*?)\)|\s*::v-deep\b|\s*>>>|\s*\/deep\/)(.*)\z/m))
        before = m[1].strip
        inner  = (m[2] || m[3]).to_s.strip
        after  = m[4].to_s.strip
        rest   = [inner, after].reject(&:empty?).join(' ')
        return rest if before.empty? # ":deep(.a)" alone scopes nothing
        return "#{scope_compound(before)} #{rest}".strip
      end

      # :slotted(x) -> x gets the slot scope attribute.
      if (m = sel.match(/\A(.*?):slotted\((.*)\)(.*)\z/m))
        before, inner, after = m[1].strip, m[2].strip, m[3].strip
        scoped_inner = scope_compound(inner, attr: @slot_attr)
        return [before, scoped_inner + after].reject(&:empty?).join(' ')
      end

      scope_compound(sel)
    end

    # Append the scope attribute to the last compound selector, before any pseudo-element.
    def scope_compound(sel, attr: @attr)
      sel = sel.strip
      return sel if sel.empty?

      compounds = split_compounds(sel)
      last = compounds.pop
      compounds.push(insert_attr(last, attr))
      compounds.join
    end

    # Split "a > b ~ c" into ["a > ", "b ~ ", "c"] keeping combinators attached to the previous part.
    def split_compounds(sel)
      parts = []
      buf = +''
      depth = 0
      quote = nil
      i = 0
      while i < sel.length
        c = sel[i]
        if quote
          quote = nil if c == quote && sel[i - 1] != '\\'
          buf << c
        elsif c == '"' || c == "'"
          quote = c
          buf << c
        elsif c == '('
          depth += 1
          buf << c
        elsif c == ')'
          depth -= 1
          buf << c
        elsif depth.zero? && (c =~ /\s/ || c == '>' || c == '+' || c == '~')
          # consume the whole combinator run
          j = i
          j += 1 while j < sel.length && (sel[j] =~ /\s/ || sel[j] == '>' || sel[j] == '+' || sel[j] == '~')
          buf << sel[i...j]
          parts << buf
          buf = +''
          i = j
          next
        else
          buf << c
        end
        i += 1
      end
      parts << buf unless buf.empty?
      parts
    end

    def insert_attr(compound, attr)
      # Split off pseudo-elements (::before, :before, :after, :first-line...) which must come last.
      if (m = compound.match(/\A(.*?)((?:::[\w-]+(?:\([^)]*\))?|:(?:before|after|first-line|first-letter|selection|placeholder|marker|backdrop)\b)+)\z/m))
        base, pseudo = m[1], m[2]
        return "#{base.empty? ? '*' : base}#{attr}#{pseudo}"
      end
      compound.empty? ? "*#{attr}" : "#{compound}#{attr}"
    end
  end
end
