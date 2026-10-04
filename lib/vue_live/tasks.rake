# frozen_string_literal: true

namespace :vue_live do
  desc 'Compile every .vue component into static .vue.js modules (default: public/vue)'
  task :precompile do
    Rake::Task['environment'].invoke if Rake::Task.task_defined?('environment')
    VueLive.load_config_file unless VueLive.rails?
    manifest = VueLive::Precompiler.new.run
    puts "  #{manifest.size} file(s) written to #{VueLive.config.precompile_dir}"
  end

  desc 'Remove precompiled components and the compile cache'
  task :clobber do
    Rake::Task['environment'].invoke if Rake::Task.task_defined?('environment')
    VueLive::Precompiler.new.clobber
    VueLive.store.clear
    puts "  removed #{VueLive.config.precompile_dir} and #{VueLive.config.cache_dir}"
  end

  desc 'Verify the configuration, component directory and (if used) the Node toolchain'
  task :check do
    Rake::Task['environment'].invoke if Rake::Task.task_defined?('environment')
    VueLive.load_config_file unless VueLive.rails?
    problems = VueLive::NodeTools.problems
    components = VueLive.store.resolver.components
    puts "  root:       #{VueLive.config.root}"
    puts "  components: #{VueLive.config.source_dir} (#{components.size} .vue file(s))"
    puts "  prefix:     #{VueLive.config.normalized_prefix}"
    puts "  compiler:   #{VueLive.config.compiler}"
    puts "  vue:        #{VueLive.config.resolved_vue_url}"
    puts "  node:       #{VueLive::NodeTools.node_version || 'not found'}"
    puts "  compiler-sfc: #{VueLive::NodeTools.compiler_sfc_version || 'not installed'}"
    if problems.empty?
      puts 'Everything looks good.'
    else
      problems.each { |p| puts "  problem:    #{p}" }
      exit 1
    end
  end

  desc 'Install @vue/compiler-sfc and vue with npm/yarn for the :node compiler'
  task :node_setup do
    Rake::Task['environment'].invoke if Rake::Task.task_defined?('environment')
    VueLive::NodeTools.setup
  end
end

if VueLive.config.hook_assets_precompile && Rake::Task.task_defined?('assets:precompile')
  Rake::Task['assets:precompile'].enhance(['vue_live:precompile'])
end
