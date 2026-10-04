# frozen_string_literal: true

require 'json'
require 'base64'

module VueLive
  # Minimal source map (v3) writer: enough to map generated lines back to lines of the .vue file.
  #
  #   map = SourceMap.new('App.vue', source)
  #   map.add(generated_line: 3, original_line: 12)          # 1-based
  #   map.to_h  / map.to_json  / map.inline_comment
  class SourceMap
    BASE64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

    attr_reader :file, :source

    def initialize(file, source, generated_file: "#{file}.js")
      @file = file
      @source = source
      @generated_file = generated_file
      @mappings = {} # generated line (1-based) => [[gen_col, orig_line, orig_col], ...]
    end

    def add(generated_line:, original_line:, generated_column: 0, original_column: 0)
      (@mappings[generated_line] ||= []) << [generated_column, original_line, original_column]
      self
    end

    # Map +count+ consecutive generated lines starting at +generated_line+ to the source lines
    # starting at +original_line+.
    def add_block(generated_line:, original_line:, count:)
      count.times { |i| add(generated_line: generated_line + i, original_line: original_line + i) }
      self
    end

    def empty?
      @mappings.empty?
    end

    def to_h
      {
        'version' => 3,
        'file' => @generated_file,
        'sources' => [file],
        'sourcesContent' => [source],
        'names' => [],
        'mappings' => encode_mappings
      }
    end

    def to_json(*)
      JSON.generate(to_h)
    end

    # `//# sourceMappingURL=data:...` line for a map Hash (this one or a backend-supplied one).
    def self.inline_comment(map_hash)
      data = Base64.strict_encode64(JSON.generate(map_hash))
      "//# sourceMappingURL=data:application/json;charset=utf-8;base64,#{data}\n"
    end

    def inline_comment
      self.class.inline_comment(to_h)
    end

    def self.vlq(value)
      vlq = value.negative? ? ((-value) << 1) | 1 : value << 1
      out = +''
      loop do
        digit = vlq & 0x1f
        vlq >>= 5
        digit |= 0x20 if vlq.positive?
        out << BASE64[digit]
        break unless vlq.positive?
      end
      out
    end

    private

    def encode_mappings
      last_line = @mappings.keys.max || 0
      prev_orig_line = 0
      prev_orig_col = 0
      (1..last_line).map do |line|
        segments = (@mappings[line] || []).sort_by(&:first)
        prev_gen_col = 0
        segments.map do |gen_col, orig_line, orig_col|
          seg = self.class.vlq(gen_col - prev_gen_col) +
                self.class.vlq(0) + # source index (always the one .vue file)
                self.class.vlq((orig_line - 1) - prev_orig_line) +
                self.class.vlq(orig_col - prev_orig_col)
          prev_gen_col = gen_col
          prev_orig_line = orig_line - 1
          prev_orig_col = orig_col
          seg
        end.join(',')
      end.join(';')
    end
  end
end
