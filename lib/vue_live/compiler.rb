# frozen_string_literal: true

require 'digest'
require_relative 'sfc/parser'

module VueLive
  # Turns a .vue source into the pieces of an ES module.  Two backends implement the same
  # interface:
  #
  #   VueLive::Compiler::Ruby  - pure Ruby, no dependencies.  Templates stay as strings and are
  #                              compiled in the browser by Vue's full build.
  #   VueLive::Compiler::Node  - @vue/compiler-sfc via Node.js.  Templates become render
  #                              functions; <script setup>, TypeScript and preprocessors work.
  module Compiler
    # What a backend hands back.  +code+ is the module body *without* style injection and
    # before import rewriting; Emitter finishes the job.
    # +source_map+ is an optional source map (Hash, v3) whose generated lines refer to +code+.
    Result = Struct.new(:code, :css, :source_map, :scope_id, :backend, :dependencies, keyword_init: true) do
      def css?
        css && !css.strip.empty?
      end
    end

    # Deterministic scope id for a component, derived from its path relative to the component
    # root so it is stable across machines and deploys: "data-v-1a2b3c4d".
    def self.scope_id(relative_path)
      "data-v-#{Digest::SHA256.hexdigest(relative_path.to_s.tr('\\', '/'))[0, 8]}"
    end

    # Pick a backend for +descriptor+ according to the configured strategy.
    def self.for(descriptor, config = VueLive.config)
      case config.compiler.to_s
      when 'ruby' then Ruby.new(config)
      when 'node' then Node.new(config)
      when 'auto', ''
        if descriptor.advanced_features.empty?
          Ruby.new(config)
        elsif Node.available?(config)
          Node.new(config)
        else
          raise UnsupportedFeature.new(
            "uses #{descriptor.advanced_features.join(', ')}, which the pure Ruby compiler cannot handle. " \
            'Install Node.js and @vue/compiler-sfc (`vue_live node-setup`) to enable the Node backend,' \
            'or rewrite the component with a plain <script> / <style> block.',
            file: descriptor.filename
          )
        end
      else
        raise Error, "unknown compiler #{config.compiler.inspect} (expected :ruby, :node or :auto)"
      end
    end

    # Parse + compile in one go.  +relative_path+ is the component's path under the source dir
    # and +absolute_path+ (optional) lets `src="..."` attributes resolve sibling files.
    def self.compile(source, relative_path:, absolute_path: nil, config: VueLive.config)
      descriptor = SFC::Parser.parse(source, filename: relative_path)
      backend = self.for(descriptor, config)
      backend.compile(descriptor, relative_path: relative_path, absolute_path: absolute_path)
    end

    class Base
      attr_reader :config

      def initialize(config = VueLive.config)
        @config = config
      end

      def name
        self.class.name.split('::').last.downcase.to_sym
      end

      # Resolve a block's `src="./file"` attribute against the component's own location.
      # Returns [content, path] or [block.content, nil].
      def block_source(block, absolute_path, dependencies)
        return [block&.content, nil] unless block&.src
        raise CompileError.new('src="..." attributes need the component path', file: absolute_path) unless absolute_path

        path = File.expand_path(block.src, File.dirname(absolute_path))
        root = File.expand_path(config.source_dir)
        unless path.start_with?(root + File::SEPARATOR)
          raise ForbiddenPath, "#{block.src} resolves outside the component root"
        end
        raise CompileError.new("src file not found: #{block.src}", file: absolute_path) unless File.file?(path)

        dependencies << path
        [File.read(path), path]
      end
    end
  end
end

require_relative 'compiler/ruby'
require_relative 'compiler/node'
