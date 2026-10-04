# frozen_string_literal: true

require 'json'

module VueLive
  # Development live reload: a Server-Sent Events stream at <prefix>/-/events that announces
  # changed components, and a small client (<prefix>/-/reload.js) that reloads the page.
  #
  # The stream polls the component directory's mtimes (config.live_reload_interval seconds) from
  # the request's own thread, so it works with any threaded Rack server (Puma, Falcon, WEBrick)
  # without extra processes or websockets.  On Rack 3 it is a streaming body (`call(io)`), which
  # servers write through unbuffered; on Rack 2 it is an `each` body.
  class LiveReload
    CLIENT = File.expand_path('assets/reload.js', __dir__)
    HEARTBEAT = 5 # seconds between keep-alive comments (also how fast a gone client is noticed)

    attr_reader :config

    def initialize(config)
      @config = config
    end

    def enabled?
      config.live_reload?
    end

    # Rack response for the SSE stream.
    def stream_response(_env = nil)
      headers = {
        'content-type' => 'text/event-stream; charset=utf-8',
        'cache-control' => 'no-store',
        'x-accel-buffering' => 'no' # nginx: do not buffer
      }
      body = LiveReload.rack3? ? StreamingBody.new(config, self) : Stream.new(config, self)
      [200, headers, body]
    end

    def client_response
      body = File.read(CLIENT)
      [200, { 'content-type' => 'text/javascript; charset=utf-8', 'cache-control' => 'no-cache',
              'content-length' => body.bytesize.to_s }, [body]]
    end

    # Snapshot of every servable file's mtime under the component root.
    def snapshot
      resolver = Resolver.new(config)
      root = resolver.source_dir
      resolver.files.each_with_object({}) do |rel, h|
        h[rel] = File.mtime(File.join(root, rel)).to_f
      rescue Errno::ENOENT
        next
      end
    end

    # Files whose mtime differs between two snapshots (added, removed or modified).
    def self.diff(before, after)
      (before.keys | after.keys).reject { |k| before[k] == after[k] }.sort
    end

    def self.rack3?
      defined?(::Rack::RELEASE) && ::Rack::RELEASE.to_s.split('.').first.to_i >= 3
    end

    # Produces SSE frames until the consumer raises (client gone), +stop+ is called, or the
    # stream reaches MAX_LIFETIME (the client reconnects at once; the cap keeps servers that join
    # request threads on shutdown, such as WEBrick, from waiting on an idle tab forever).
    class Frames
      MAX_LIFETIME = 30 # seconds

      def initialize(config, reloader)
        @config = config
        @reloader = reloader || LiveReload.new(config)
        @stopped = false
      end

      def stop
        @stopped = true
      end

      def each_frame
        last = @reloader.snapshot # before the first frame, so nothing slips through the gap
        yield "retry: 1000\n\n"
        yield ": connected\n\n"
        started = last_beat = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        until @stopped
          sleep @config.live_reload_interval
          current = @reloader.snapshot
          changed = LiveReload.diff(last, current)
          unless changed.empty?
            VueLive.store.clear if @config.reload? # make sure the next request recompiles
            yield "event: change\ndata: #{JSON.generate(files: changed)}\n\n"
            last = current
          end
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          break if now - started >= MAX_LIFETIME

          if now - last_beat >= HEARTBEAT
            yield ": ping\n\n"
            last_beat = now
          end
        end
      rescue Errno::EPIPE, Errno::ECONNRESET, Errno::ENOTCONN, IOError
        nil # client went away
      end
    end

    # Rack 2 style body: the server pulls frames with #each.
    class Stream < Frames
      def each(&block)
        each_frame(&block)
      end

      def close
        stop
      end
    end

    # Rack 3 streaming body: the server hands us the connection and we push frames into it.
    # Deliberately has no #each, otherwise servers would buffer it as an ordinary body.
    class StreamingBody < Frames
      def call(io)
        each_frame do |frame|
          io.write(frame)
          io.flush if io.respond_to?(:flush)
        end
      ensure
        begin
          io.close if io.respond_to?(:close)
        rescue IOError, SystemCallError
          nil
        end
      end
    end
  end
end
