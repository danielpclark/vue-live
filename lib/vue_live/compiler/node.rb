# frozen_string_literal: true

require 'json'
require 'open3'

module VueLive
  module Compiler
    # Backend that shells out to Node.js and @vue/compiler-sfc (lib/vue_live/compiler/node/compile.js).
    #
    # Templates are compiled to render functions, so the runtime-only Vue build is enough;
    # <script setup>, TypeScript, Pug, Sass/Less/Stylus and CSS modules all work when the matching
    # npm packages are installed in the project.  Each compile is one short-lived `node` process,
    # which is why results are cached.
    class Node < Base
      SCRIPT = File.expand_path('node/compile.js', __dir__)

      @availability = {}
      @mutex = Mutex.new

      class << self
        # true when `node` runs and @vue/compiler-sfc resolves from the project root.
        def available?(config = VueLive.config)
          key = [config.node_bin, config.root]
          @mutex.synchronize do
            return @availability[key] if @availability.key?(key)
            @availability[key] = probe(config)
          end
        end

        def reset!
          @mutex.synchronize { @availability.clear }
        end

        private

        def probe(config)
          out, status = Open3.capture2e(
            config.node_bin, '-e',
            "require.resolve('@vue/compiler-sfc', { paths: [process.argv[1]] })",
            config.root.to_s
          )
          status.success? || (config.logger.debug("[vue_live] Node backend unavailable: #{out.strip}") && false)
        rescue Errno::ENOENT, Errno::EACCES
          false
        end
      end

      def compile(descriptor, relative_path:, absolute_path: nil)
        scope_id = Compiler.scope_id(relative_path)
        payload = {
          source: descriptor.source,
          filename: relative_path,
          absolutePath: absolute_path,
          scopeId: scope_id,
          isProd: config.production?
        }

        out, err, status = Open3.capture3(config.node_bin, SCRIPT, config.root.to_s, stdin_data: JSON.generate(payload))
        result = parse_output(out, err, status, relative_path)

        Result.new(code: result['code'].to_s, css: result['css'].to_s,
                   scope_id: result['scoped'] ? scope_id : nil, backend: :node,
                   dependencies: Array(result['dependencies']))
      rescue Errno::ENOENT
        raise CompileError.new("Node.js executable not found: #{config.node_bin}", file: relative_path)
      end

      private

      def parse_output(out, err, status, relative_path)
        data = JSON.parse(out)
        unless data['errors'].nil? || data['errors'].empty?
          raise CompileError.new(data['errors'].join("\n"), file: relative_path)
        end
        Array(data['tips']).each { |tip| config.logger.warn("[vue_live] #{relative_path}: #{tip}") }
        raise CompileError.new(err.strip.empty? ? 'node exited with an error' : err.strip, file: relative_path) unless status.success?
        data
      rescue JSON::ParserError
        raise CompileError.new("unexpected output from compile.js: #{(err + out).strip}", file: relative_path)
      end
    end
  end
end
