# frozen_string_literal: true

module VueLive
  module SFC
    # One top-level block of a single-file component: <template>, <script>, <style> or a custom block.
    class Block
      attr_reader :type, :content, :attrs, :line

      def initialize(type:, content:, attrs: {}, line: 1)
        @type = type
        @content = content
        @attrs = attrs
        @line = line
      end

      def lang
        attrs['lang']
      end

      def src
        attrs['src']
      end

      def setup?
        attrs.key?('setup')
      end

      def scoped?
        attrs.key?('scoped')
      end

      def module?
        attrs.key?('module')
      end

      def attr?(name)
        attrs.key?(name)
      end
    end

    # The parsed shape of a .vue file.  Mirrors @vue/compiler-sfc's SFCDescriptor closely enough
    # that both compiler backends can reason about the same thing.
    class Descriptor
      attr_reader :filename, :source, :template, :script, :script_setup, :styles, :custom_blocks

      def initialize(filename:, source:, template: nil, script: nil, script_setup: nil, styles: [], custom_blocks: [])
        @filename = filename
        @source = source
        @template = template
        @script = script
        @script_setup = script_setup
        @styles = styles
        @custom_blocks = custom_blocks
      end

      def scoped_styles?
        styles.any?(&:scoped?)
      end

      def css_modules?
        styles.any?(&:module?)
      end

      def template_lang
        template&.lang
      end

      def script_lang
        (script_setup || script)&.lang
      end

      # Features the pure Ruby backend cannot provide.  Empty means "Ruby can compile this".
      def advanced_features
        features = []
        features << '<script setup>' if script_setup
        features << "<script lang=\"#{script_lang}\">" if script_lang && !%w[js javascript].include?(script_lang)
        features << "<template lang=\"#{template_lang}\">" if template_lang && template_lang != 'html'
        styles.each do |s|
          features << "<style lang=\"#{s.lang}\">" if s.lang && !%w[css postcss].include?(s.lang)
          features << '<style module>' if s.module?
        end
        features.uniq
      end
    end
  end
end
