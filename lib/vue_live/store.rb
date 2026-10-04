# frozen_string_literal: true

require 'digest'

module VueLive
  # Compiles components on demand and remembers the result.
  #
  # In development (config.reload? == true) every fetch compares the file's mtime (and the mtimes
  # of any `src="..."` dependencies) with the cached entry and recompiles when something changed.
  # In production the first request compiles and every later one is a hash lookup.
  class Store
    attr_reader :config, :resolver, :cache

    def initialize(config)
      @config = config
      @resolver = Resolver.new(config)
      @cache = Cache.build(config)
      @locks = Hash.new { |h, k| h[k] = Mutex.new }
      @locks_mutex = Mutex.new
    end

    # Compiled module for the component at +relative_path+ (e.g. "App.vue").  Raises
    # Errno::ENOENT when the file is missing and CompileError when it cannot be compiled.
    def fetch(relative_path)
      relative_path = relative_path.sub(/\.vue\.js\z/, '.vue')
      absolute = File.join(resolver.source_dir, relative_path)
      raise Errno::ENOENT, absolute unless File.file?(absolute)

      key = cache_key(relative_path)
      hit = cache.read(key)
      return hit if hit && !stale?(hit, absolute)

      lock_for(key).synchronize do
        hit = cache.read(key)
        return hit if hit && !stale?(hit, absolute)
        compiled = compile(relative_path, absolute)
        cache.write(key, compiled)
      end
    end

    # Content digest for cache-busting URLs; nil when the component does not exist or fails.
    def digest(relative_path)
      fetch(relative_path).digest
    rescue Error, Errno::ENOENT
      nil
    end

    def clear
      cache.clear
    end

    private

    def compile(relative_path, absolute)
      source = File.read(absolute)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = Compiler.compile(source, relative_path: relative_path, absolute_path: absolute, config: config)
      code = Emitter.emit(result, relative_path: relative_path, inject_styles: config.inject_styles)
      ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)
      config.logger.debug("[vue_live] compiled #{relative_path} with #{result.backend} in #{ms}ms")

      Compiled.new(
        relative_path: relative_path,
        code: code,
        digest: Digest::SHA256.hexdigest(code)[0, 16],
        mtime: latest_mtime([absolute] + result.dependencies),
        dependencies: result.dependencies,
        backend: result.backend,
        scope_id: result.scope_id
      )
    end

    def stale?(compiled, absolute)
      return false unless config.reload?
      latest_mtime([absolute] + Array(compiled.dependencies)) > compiled.mtime
    rescue Errno::ENOENT
      true
    end

    def latest_mtime(files)
      files.map { |f| File.mtime(f) }.max
    end

    def cache_key(relative_path)
      "#{config.env}:#{config.compiler}:#{relative_path}"
    end

    def lock_for(key)
      @locks_mutex.synchronize { @locks[key] }
    end
  end
end
