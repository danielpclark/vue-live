# frozen_string_literal: true

require 'digest'

module VueLive
  # Compiles components on demand and remembers the result.
  #
  # In development (config.reload? == true) every fetch compares the file's mtime (and the mtimes
  # of any `src="..."` dependencies and imported siblings) with the cached entry and recompiles
  # when something changed.  In production the first request compiles and every later one is a
  # hash lookup.
  #
  # With config.digest_imports the relative imports inside a module get `?v=<digest>` appended,
  # so a page's whole module graph can be served with immutable caching: a child's digest is part
  # of its parent's code, and therefore of the parent's digest.
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

        compiling.push(relative_path)
        begin
          compiled = compile(relative_path, absolute)
        ensure
          compiling.pop
        end
        cache.write(key, compiled)
      end
    end

    # Content digest for cache-busting URLs; nil when the component does not exist or fails.
    def digest(relative_path)
      fetch(relative_path).digest
    rescue Error, Errno::ENOENT
      nil
    end

    # Cache-busting token for a non-component file under the root (matches the middleware's ETag).
    def file_digest(relative_path)
      stat = File.stat(File.join(resolver.source_dir, relative_path))
      Store.file_etag(stat)
    rescue Errno::ENOENT
      nil
    end

    def self.file_etag(stat)
      "#{stat.mtime.to_i.to_s(16)}-#{stat.size.to_s(16)}"
    end

    def clear
      cache.clear
    end

    private

    def compile(relative_path, absolute)
      source = File.read(absolute)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = Compiler.compile(source, relative_path: relative_path, absolute_path: absolute, config: config)
      dependencies = result.dependencies.dup
      code = Emitter.emit(result, relative_path: relative_path, inject_styles: config.inject_styles,
                                  source_map: config.source_maps?) do |spec|
        digest_import(spec, relative_path, dependencies)
      end
      ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)
      config.logger.debug("[vue_live] compiled #{relative_path} with #{result.backend} in #{ms}ms")

      Compiled.new(
        relative_path: relative_path,
        code: code,
        digest: Digest::SHA256.hexdigest(code)[0, 16],
        mtime: latest_mtime([absolute] + dependencies),
        dependencies: dependencies,
        backend: result.backend,
        scope_id: result.scope_id
      )
    end

    # `./Child.vue.js` -> `./Child.vue.js?v=<digest>` (compiling the child if needed);
    # `./util.js` -> `./util.js?v=<mtime-size>`.  Imports that cannot be resolved are left alone.
    def digest_import(spec, importer, dependencies)
      return nil unless config.digest_imports
      return nil if spec.start_with?('/') # absolute URLs may belong to another mount

      target = resolver.resolve(File.expand_path(spec, "/#{File.dirname(importer)}").sub(%r{\A/}, ''))
      return nil unless target

      dependencies << target.absolute_path
      token = if target.vue?
                compiling.include?(target.relative_path) ? nil : digest(target.relative_path)
              else
                file_digest(target.relative_path)
              end
      token ? "#{spec}?v=#{token}" : nil
    end

    # Components whose compilation is in progress on this thread, to break import cycles.
    def compiling
      Thread.current[:vue_live_compiling] ||= []
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
