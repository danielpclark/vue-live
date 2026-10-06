# frozen_string_literal: true

require 'fileutils'
require_relative '../vue_live'

module VueLive
  # The `vue_live` executable.
  class CLI
    TEMPLATE_DIR = File.expand_path('templates', __dir__)

    USAGE = <<~TEXT.freeze
      vue_live #{VueLive::VERSION}

      Usage: vue_live <command> [options]

      Commands:
        init         Create config/vue_live.yml and app/vue/ with an example component
                       --force        overwrite existing files
                       --node         also install @vue/compiler-sfc + vue (npm/yarn)
        compile      Write static .vue.js modules + manifest.json  (--out DIR, default public/vue)
        clobber      Remove precompiled output and the compile cache
        check        Verify configuration, components and the Node toolchain
        node-setup   Install @vue/compiler-sfc and vue  (--with pkg[,pkg]  e.g. --with sass,esbuild);
                       adds the sucrase TypeScript transpiler when Node.js < 22.13
        info         Show versions and resolved settings
        version      Show the vue_live version

      The environment comes from VUE_LIVE_ENV, RAILS_ENV, RACK_ENV or APP_ENV (default: development).
      In a Rails project prefer `bin/rails generate vue_live:install` and the `vue_live:*` rake tasks.
    TEXT

    def self.start(argv = ARGV, out: $stdout, err: $stderr)
      new(argv, out, err).run
    end

    def initialize(argv, out = $stdout, err = $stderr)
      @command, *@args = argv
      @out = out
      @err = err
    end

    def run
      VueLive.load_config_file if %w[compile clobber check info].include?(@command)
      case @command
      when 'init' then init
      when 'compile' then compile
      when 'clobber' then clobber
      when 'check' then check
      when 'node-setup' then node_setup
      when 'info' then info
      when 'version', '--version', '-v' then @out.puts VueLive::VERSION
      when nil, 'help', '--help', '-h' then @out.puts USAGE
      else
        @err.puts "Unknown command: #{@command}\n\n#{USAGE}"
        return 1
      end
      0
    rescue VueLive::Error => e
      @err.puts e.message
      1
    end

    private

    def root
      VueLive.config.root
    end

    def init
      force = @args.include?('--force')
      if VueLive.rails_project?(root)
        @out.puts 'Rails project detected: creating the same files `bin/rails generate vue_live:install` would.'
      end
      write('config/vue_live.yml', File.read(File.join(TEMPLATE_DIR, 'vue_live.yml')), force)
      FileUtils.mkdir_p(File.join(root, VueLive.config.source_path))
      write(File.join(VueLive.config.source_path, 'HelloVueLive.vue'), File.read(File.join(TEMPLATE_DIR, 'HelloVueLive.vue')),
            force)
      NodeTools.setup(root) if @args.include?('--node')
      @out.puts ''
      @out.puts 'Done.  Mount the middleware (`use VueLive::Middleware`, or `register VueLive::Sinatra`) and render:'
      @out.puts ''
      @out.puts '    <%= vue_live_import_map_tag %>'
      @out.puts '    <%= vue_live_mount_tag "HelloVueLive.vue", "#app", element: true %>'
    end

    def compile
      out_dir = option_value('--out') || VueLive.config.precompile_dir
      manifest = Precompiler.new.run(output: File.expand_path(out_dir, root), out: @out)
      @out.puts "  #{manifest.size} file(s) written to #{out_dir}"
    end

    def clobber
      Precompiler.new.clobber
      VueLive.store.clear
      @out.puts "  removed #{VueLive.config.precompile_dir} and #{VueLive.config.cache_dir}"
    end

    def check
      problems = NodeTools.problems
      components = VueLive.store.resolver.components
      @out.puts "  components: #{VueLive.config.source_dir} (#{components.size} .vue file(s))"
      components.each do |c|
        compiled = VueLive.store.fetch(c)
        @out.puts "    ok     #{c} (#{compiled.backend})"
      rescue VueLive::Error => e
        problems << e.message
        @out.puts "    FAIL   #{c}"
      end
      if problems.empty?
        @out.puts 'Everything looks good.'
      else
        problems.each { |p| @out.puts "  problem: #{p}" }
        raise Error, "#{problems.size} problem(s) found"
      end
    end

    def node_setup
      extra = option_value('--with').to_s.split(',').map(&:strip).reject(&:empty?)
      NodeTools.setup(root, packages: NodeTools::PACKAGES + extra)
      @out.puts 'Node backend ready: set `compiler: node` (or leave `auto`) in config/vue_live.yml.'
    end

    def info
      cfg = VueLive.config
      {
        'vue_live' => VueLive::VERSION,
        'ruby' => RUBY_VERSION,
        'root' => cfg.root,
        'env' => cfg.env,
        'rails project' => VueLive.rails_project?(cfg.root),
        'components' => cfg.source_dir,
        'prefix' => cfg.normalized_prefix,
        'compiler' => cfg.compiler,
        'cache' => cfg.cache,
        'vue url' => cfg.resolved_vue_url,
        'node' => NodeTools.node_version || 'not found',
        '@vue/compiler-sfc' => NodeTools.compiler_sfc_version || 'not installed',
        'package manager' => NodeTools.package_manager,
        'webpacker_cli' => NodeTools.webpacker_cli? ? 'available' : 'not installed'
      }.each { |k, v| @out.puts "#{k}: #{v}" }
    end

    def write(rel, content, force)
      path = File.join(root, rel)
      if File.exist?(path) && !force
        @out.puts "   exist  #{rel}"
        return
      end
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
      @out.puts "  create  #{rel}"
    end

    def option_value(flag)
      idx = @args.index(flag)
      return @args[idx + 1] if idx && @args[idx + 1]

      @args.find { |a| a.start_with?("#{flag}=") }&.split('=', 2)&.last
    end
  end
end
