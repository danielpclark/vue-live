# frozen_string_literal: true

require 'open3'
require 'json'

module VueLive
  # Optional Node.js plumbing for the :node compiler backend.
  #
  # When the webpacker_cli gem is available its conventions are reused (package manager detection,
  # project layout); otherwise a yarn.lock / package-lock.json sniff decides between yarn and npm.
  module NodeTools
    PACKAGES = ['@vue/compiler-sfc', 'vue'].freeze

    module_function

    def webpacker_cli?
      return true if defined?(::WebpackerCli)
      require 'webpacker_cli'
      true
    rescue LoadError
      false
    end

    def node_version(config = VueLive.config)
      out, status = Open3.capture2e(config.node_bin, '--version')
      status.success? ? out.strip : nil
    rescue Errno::ENOENT
      nil
    end

    def package_manager(root = VueLive.config.root)
      return ::WebpackerCli.package_manager(root) if webpacker_cli?
      return 'npm' if File.exist?(File.join(root, 'package-lock.json')) && !File.exist?(File.join(root, 'yarn.lock'))
      return 'yarn' if File.exist?(File.join(root, 'yarn.lock')) || which('yarn')
      'npm'
    end

    def compiler_sfc_version(root = VueLive.config.root)
      JSON.parse(File.read(File.join(root, 'node_modules', '@vue', 'compiler-sfc', 'package.json')))['version']
    rescue StandardError
      nil
    end

    def vue_version(root = VueLive.config.root)
      JSON.parse(File.read(File.join(root, 'node_modules', 'vue', 'package.json')))['version']
    rescue StandardError
      nil
    end

    # Install @vue/compiler-sfc (and vue, for a local copy of the browser build) into the project.
    def setup(root = VueLive.config.root, packages: PACKAGES, dev: true)
      raise Error, 'Node.js was not found in PATH; install it to use the :node compiler' unless node_version
      pkg_json = File.join(root, 'package.json')
      File.write(pkg_json, JSON.pretty_generate('name' => File.basename(root), 'private' => true)) unless File.exist?(pkg_json)
      manager = package_manager(root)
      cmd = if manager == 'yarn'
              ['yarn', 'add', *(dev ? ['--dev'] : []), *packages]
            else
              ['npm', 'install', *(dev ? ['--save-dev'] : []), *packages]
            end
      puts "  run    #{cmd.join(' ')}"
      success = system(*cmd, chdir: root)
      raise Error, "#{manager} failed to install #{packages.join(', ')}" unless success
      Compiler::Node.reset!
      true
    end

    # Human-readable status for `vue-live check`.
    def problems(config = VueLive.config)
      problems = []
      problems << "component directory does not exist: #{config.source_dir}" unless File.directory?(config.source_dir)
      if %i[node].include?(config.compiler.to_sym)
        problems << 'Node.js was not found in PATH (required by compiler: node)' unless node_version(config)
        problems << '@vue/compiler-sfc is not installed (run `vue-live node-setup`)' unless compiler_sfc_version(config.root)
      end
      problems
    end

    def which(cmd)
      ENV['PATH'].to_s.split(File::PATH_SEPARATOR).any? do |p|
        f = File.join(p, cmd)
        File.executable?(f) && !File.directory?(f)
      end
    end
  end
end
