# frozen_string_literal: true

require 'json'
require 'open3'
require 'io/wait'

module VueLive
  module Compiler
    # Backend that drives @vue/compiler-sfc through Node.js (lib/vue_live/compiler/node/compile.js).
    #
    # Templates are compiled to render functions, so the runtime-only Vue build is enough;
    # <script setup>, TypeScript, Pug, Sass/Less/Stylus and CSS modules all work when the matching
    # npm packages are installed in the project.
    #
    # Requests go to a long-lived worker process (one per configuration), so after the first
    # compile each one costs a few milliseconds instead of a Node start-up.  Set
    # config.node_worker = false to spawn one process per compile instead.
    class Node < Base
      SCRIPT = File.expand_path('node/compile.js', __dir__)
      REQUEST_TIMEOUT = 60 # seconds; a hung worker is killed and restarted

      @availability = {}
      @workers = {}
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
          @mutex.synchronize do
            @availability.clear
            @workers.each_value(&:stop)
            @workers.clear
          end
        end

        # The shared worker for +config+ (started on first use).
        def worker_for(config)
          key = [config.node_bin, config.root.to_s]
          @mutex.synchronize { @workers[key] ||= Worker.new(config) }
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
          isProd: config.production?,
          sourceMap: config.source_maps?
        }

        data = if config.node_worker
                 self.class.worker_for(config).request(payload)
               else
                 one_shot(payload)
               end
        check_errors!(data, relative_path)

        Result.new(code: data['code'].to_s, css: data['css'].to_s, source_map: data['map'],
                   scope_id: data['scoped'] ? scope_id : nil, backend: :node,
                   dependencies: Array(data['dependencies']))
      rescue Errno::ENOENT
        raise CompileError.new("Node.js executable not found: #{config.node_bin}", file: relative_path)
      end

      private

      def one_shot(payload)
        out, err, status = Open3.capture3(config.node_bin, SCRIPT, config.root.to_s, stdin_data: JSON.generate(payload))
        data = JSON.parse(out)
        if !status.success? && Array(data['errors']).empty?
          data['errors'] =
            [err.strip.empty? ? 'node exited with an error' : err.strip]
        end
        data
      rescue JSON::ParserError
        { 'errors' => ["unexpected output from compile.js: #{(err.to_s + out.to_s).strip}"] }
      end

      def check_errors!(data, relative_path)
        errors = Array(data['errors'])
        raise CompileError.new(errors.join("\n"), file: relative_path) unless errors.empty?

        Array(data['tips']).each { |tip| config.logger.warn("[vue_live] #{relative_path}: #{tip}") }
      end

      # A `node compile.js --server` process speaking newline-delimited JSON over stdin/stdout.
      # Requests are serialised with a mutex; the worker is restarted transparently when it dies.
      class Worker
        def initialize(config)
          @config = config
          @mutex = Mutex.new
          @sequence = 0
          @pid = nil
          at_exit { stop }
        end

        def request(payload)
          @mutex.synchronize do
            attempts = 0
            loop do
              attempts += 1
              start unless alive?
              begin
                return exchange(payload)
              rescue WorkerDied => e
                stop
                raise CompileError.new("Node worker failed: #{e.message}", file: payload[:filename]) if attempts >= 2

                @config.logger.warn("[vue_live] Node worker died (#{e.message}); restarting")
              end
            end
          end
        end

        def alive?
          @pid && @wait_thread&.alive?
        end

        def stop
          return unless @pid

          begin
            @stdin&.close
          rescue IOError
            nil
          end
          begin
            Process.kill('TERM', @pid)
          rescue Errno::ESRCH, Errno::EPERM
            nil
          end
          @wait_thread&.join(2)
          @stdout&.close unless @stdout&.closed?
          @stderr&.close unless @stderr&.closed?
        ensure
          @pid = nil
        end

        private

        class WorkerDied < StandardError; end

        def start
          @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(@config.node_bin, SCRIPT, @config.root.to_s, '--server')
          @pid = @wait_thread.pid
          @stdin.sync = true
          @config.logger.debug("[vue_live] started Node worker pid #{@pid}")
        end

        def exchange(payload)
          @sequence += 1
          id = @sequence
          begin
            @stdin.puts(JSON.generate(payload.merge(id: id)))
          rescue Errno::EPIPE, IOError => e
            raise WorkerDied, e.message
          end

          line = read_line_with_timeout
          data = JSON.parse(line)
          raise WorkerDied, "response id mismatch (#{data['id']} != #{id})" if data.key?('id') && data['id'] != id

          data
        rescue JSON::ParserError => e
          raise WorkerDied, "bad response: #{e.message}"
        end

        def read_line_with_timeout
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + REQUEST_TIMEOUT
          loop do
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            raise WorkerDied, 'timed out waiting for compile.js' if remaining <= 0

            next unless @stdout.wait_readable(remaining)

            line = @stdout.gets
            raise WorkerDied, "exited: #{drain_stderr}" if line.nil?

            return line
          end
        end

        def drain_stderr
          @stderr.read_nonblock(8192).to_s.strip
        rescue IO::WaitReadable, IOError, SystemCallError
          ''
        end
      end
    end
  end
end
