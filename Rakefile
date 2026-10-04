require 'bundler/gem_tasks'
require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test' << 'lib'
  t.test_files = FileList['test/**/*_test.rb']
  t.warning = false
end

namespace :test do
  desc 'Install the Node packages (and a Chromium) that the Node-backend and browser tests need'
  task :setup do
    dir = File.expand_path('test', __dir__)
    manager = File.exist?(File.join(dir, 'yarn.lock')) ? 'yarn' : 'npm'
    sh manager, 'install', chdir: dir
    sh File.join(dir, 'node_modules', '.bin', 'playwright-core'), 'install', 'chromium' do |ok, _|
      warn 'Chromium download failed; set PLAYWRIGHT_CHROMIUM to an existing browser to run the e2e test' unless ok
    end
  end
end

begin
  require 'rubocop/rake_task'
  RuboCop::RakeTask.new
  task default: %i[rubocop test]
rescue LoadError
  task default: :test
end
