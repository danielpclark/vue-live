# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'

module VueLive
  # A compiled component as served to the browser.
  Compiled = Struct.new(:relative_path, :code, :digest, :mtime, :dependencies, :backend, :scope_id, keyword_init: true) do
    def etag
      %("#{digest}")
    end

    def to_h
      { 'relative_path' => relative_path, 'code' => code, 'digest' => digest, 'mtime' => mtime.to_f,
        'dependencies' => dependencies, 'backend' => backend.to_s, 'scope_id' => scope_id }
    end

    def self.from_h(h)
      new(relative_path: h['relative_path'], code: h['code'], digest: h['digest'], mtime: Time.at(h['mtime'].to_f),
          dependencies: Array(h['dependencies']), backend: h['backend']&.to_sym, scope_id: h['scope_id'])
    end
  end

  module Cache
    def self.build(config)
      case config.cache.to_s
      when 'none' then Null.new
      when 'file' then FileStore.new(config.cache_dir, Memory.new)
      else Memory.new
      end
    end

    class Null
      def read(_key) = nil
      def write(_key, value) = value
      def delete(_key) = nil
      def clear = nil
    end

    class Memory
      def initialize
        @data = {}
        @mutex = Mutex.new
      end

      def read(key)
        @mutex.synchronize { @data[key] }
      end

      def write(key, value)
        @mutex.synchronize { @data[key] = value }
      end

      def delete(key)
        @mutex.synchronize { @data.delete(key) }
      end

      def clear
        @mutex.synchronize { @data.clear }
      end
    end

    # Persists compiled modules as JSON files so warm caches survive restarts and are shared
    # between processes (Puma workers, Sidekiq rendering emails...).  Wraps a Memory cache.
    class FileStore
      def initialize(dir, inner = Memory.new)
        @dir = dir
        @inner = inner
      end

      def read(key)
        hit = @inner.read(key)
        return hit if hit

        file = path_for(key)
        return nil unless File.file?(file)

        compiled = Compiled.from_h(JSON.parse(File.read(file)))
        @inner.write(key, compiled)
      rescue JSON::ParserError, Errno::ENOENT
        nil
      end

      def write(key, value)
        @inner.write(key, value)
        FileUtils.mkdir_p(@dir)
        tmp = "#{path_for(key)}.#{Process.pid}.tmp"
        File.write(tmp, JSON.generate(value.to_h))
        File.rename(tmp, path_for(key))
        value
      end

      def delete(key)
        @inner.delete(key)
        FileUtils.rm_f(path_for(key))
      end

      def clear
        @inner.clear
        FileUtils.rm_rf(@dir)
      end

      private

      def path_for(key)
        File.join(@dir, "#{Digest::SHA256.hexdigest(key)}.json")
      end
    end
  end
end
