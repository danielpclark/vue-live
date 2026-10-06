lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'vue_live/version'

Gem::Specification.new do |spec|
  spec.name                  = 'vue_live'
  spec.version               = VueLive::VERSION
  spec.authors               = ['Daniel P. Clark']
  spec.email                 = ['6ftdan@gmail.com']

  spec.summary               = 'Serve Vue single-file components straight from Ruby, in production, with no build step.'
  spec.description           = <<~DESC.strip
    vue_live compiles .vue single-file components on the fly, in Ruby, and serves them to the browser
    as native ES modules.  It works with any Rack application (Sinatra, Roda, plain Rack), detects a
    Rails application and configures itself as a Railtie, and coexists with Sprockets, Propshaft,
    Webpacker, importmap-rails and jsbundling without touching their paths.  An optional Node backend
    (via @vue/compiler-sfc) adds <script setup>, TypeScript and CSS preprocessors.
  DESC
  spec.licenses              = ['MIT', 'Apache-2.0']
  spec.homepage              = 'https://github.com/danielpclark/vue_live'
  spec.required_ruby_version = '>= 3.0'

  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri']   = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['bug_tracker_uri'] = "#{spec.homepage}/issues"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.chdir(__dir__) do
    Dir['lib/**/*', 'exe/*', 'LICENSE-*', 'README.md', 'CHANGELOG.md'].select { |f| File.file?(f) }
  end
  spec.bindir        = 'exe'
  spec.executables   = ['vue_live']
  spec.require_paths = ['lib']

  # No runtime dependencies on purpose: the gem must drop into any Ruby project.
  spec.add_development_dependency 'actionview', '>= 6.1', '< 9'
  spec.add_development_dependency 'importmap-rails', '>= 1.0', '< 3'
  spec.add_development_dependency 'minitest', '~> 5.11'
  spec.add_development_dependency 'rack', '>= 2.2', '< 4'
  spec.add_development_dependency 'rack-test', '~> 2.0'
  spec.add_development_dependency 'rackup', '>= 1.0', '< 3'
  spec.add_development_dependency 'railties', '>= 6.1', '< 9'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rubocop', '~> 1.60'
  spec.add_development_dependency 'sinatra', '>= 3.0', '< 5'
  spec.add_development_dependency 'webpacker_cli', '~> 1.0'
  spec.add_development_dependency 'webrick', '~> 1.8'
end
