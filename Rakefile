lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'rubygems'
require 'rubygems/package'
require 'rake/clean'
require 'rake/testtask'
require 'date'
require 'ruby_doozer/version'

desc "Build gem"
task :gem  do |t|
  gemspec = Gem::Specification.new do |spec|
    spec.name        = 'ruby_doozer'
    spec.version     = RubyDoozer::VERSION
    spec.platform    = Gem::Platform::RUBY
    spec.authors     = ['Reid Morrison']
    spec.email       = ['reidmo@gmail.com']
    spec.homepage    = 'https://github.com/ClarityServices/ruby_doozer'
    spec.date        = Date.today.to_s
    spec.summary     = "Doozer Ruby Client"
    spec.description = "Ruby Client for doozer"
    spec.files       = FileList["./**/*"].exclude(/\.gem$/, /\.log$/,/nbproject/).map{|f| f.sub(/^\.\//, '')}
    spec.license     = "Apache License V2.0"
    spec.has_rdoc    = true
    spec.add_dependency 'semantic_logger', '>= 2.1'
    spec.add_dependency 'resilient_socket', '>= 0.5.0'
    spec.add_dependency 'ruby_protobuf', '>= 0.4.11'
    spec.add_dependency 'gene_pool', '>= 1.3.0'
    spec.add_dependency 'sync_attr', '>= 1.0.0'
    spec.add_dependency 'multi_json', '>= 1.6.1'
  end
  Gem::Package.build gemspec
end

desc "Run Test Suite"
task :test do
  Rake::TestTask.new(:functional) do |t|
    t.test_files = FileList['test/*_test.rb']
    t.verbose    = true
  end

  Rake::Task['functional'].invoke
end
