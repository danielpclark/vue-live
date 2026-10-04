# frozen_string_literal: true

module VueLive
  # Maps request paths to files under the component root, refusing anything that escapes it.
  class Resolver
    Target = Struct.new(:relative_path, :absolute_path, :vue?, :digest_hint, keyword_init: true)

    def initialize(config)
      @config = config
    end

    def source_dir
      @config.source_dir
    end

    # +path+ is the request path *after* the URL prefix, e.g. "components/App.vue.js".
    # Returns a Target or nil when nothing under the root matches.
    def resolve(path)
      rel = clean(path)
      return nil if rel.nil? || rel.empty?

      rel = rel.sub(/\.vue\.js\z/, '.vue') # "App.vue.js" is the same component as "App.vue"
      ext = File.extname(rel).downcase
      return nil unless @config.extensions.include?(ext)

      root = File.expand_path(source_dir)
      abs = File.expand_path(rel, root)
      return nil unless abs.start_with?(root + File::SEPARATOR)
      return nil unless File.file?(abs)

      Target.new(relative_path: rel, absolute_path: abs, vue?: ext == '.vue')
    end

    # Every .vue component under the root, as relative paths.
    def components
      root = File.expand_path(source_dir)
      return [] unless File.directory?(root)
      Dir.glob('**/*.vue', base: root).sort
    end

    # All servable files (components and their sibling assets).
    def files
      root = File.expand_path(source_dir)
      return [] unless File.directory?(root)
      Dir.glob('**/*', base: root).select do |rel|
        File.file?(File.join(root, rel)) && @config.extensions.include?(File.extname(rel).downcase)
      end.sort
    end

    private

    def clean(path)
      return nil if path.nil?
      decoded = path.to_s.gsub(/%([0-9a-fA-F]{2})/) { Regexp.last_match(1).hex.chr }
      return nil if decoded.include?("\0") || decoded.include?('\\')
      parts = decoded.split('/').reject { |p| p.empty? || p == '.' }
      return nil if parts.any? { |p| p == '..' || p.start_with?('.') }
      parts.join('/')
    end
  end
end
