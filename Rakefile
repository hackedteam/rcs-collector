require "bundler/gem_tasks"
require 'fileutils'
require 'rbconfig'
require 'rake'

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/test_*.rb'
  test.verbose = true
end

task :default => :test


def execute(message)
  print message + '...'
  STDOUT.flush
  yield if block_given?
  puts 'ok'
rescue Exception => e
  puts "error: #{e.message}"
end


desc "Housekeeping for the project"
task :clean do
  execute "Cleaning the log directory" do
    Dir['./log/*.log'].each do |f|
      File.delete(f)
    end
    Dir['./log/err/*.log'].each do |f|
      File.delete(f)
    end
  end
  execute "Cleaning the DB cache" do
    File.delete('./config/cache.db') if File.exist?('./config/cache.db')
  end
end

desc "Remove the protected release code"
task :unprotect do
  execute "Deleting the protected release folder" do
    Dir[Dir.pwd + '/lib/rcs-collector-release/*'].each do |f|
      File.delete(f) unless File.directory?(f)
    end
    Dir[Dir.pwd + '/lib/rcs-collector-release/rgloader/*'].each do |f|
      File.delete(f) unless File.directory?(f)
    end
    Dir.delete(Dir.pwd + '/lib/rcs-collector-release/rgloader') if File.exist?(Dir.pwd + '/lib/rcs-collector-release/rgloader')
    Dir.delete(Dir.pwd + '/lib/rcs-collector-release') if File.exist?(Dir.pwd + '/lib/rcs-collector-release')
  end
end

case RbConfig::CONFIG['host_os']
  when /darwin/
    RUBYENCPATH = '/Applications/Development/RubyEncoder.app/Contents/MacOS'
    RUBYENC = "#{RUBYENCPATH}/rgencoder"
  when /mingw/
    RUBYENCPATH = 'C:/Program Files (x86)/RubyEncoder15'
    RUBYENC = "\"C:\\Program Files (x86)\\RubyEncoder15\\rgencoder.exe\""
end

desc "Create the encrypted code for release"
task :protect do
  Rake::Task[:unprotect].invoke
  execute "Creating release folder" do
    Dir.mkdir(Dir.pwd + '/lib/rcs-collector-release') if not File.directory?(Dir.pwd + '/lib/rcs-collector-release')
  end

  execute "Copying the rgloader" do
    RGPATH = RUBYENCPATH + '/Loaders'
    Dir.mkdir(Dir.pwd + '/lib/rgloader')
    files = Dir[RGPATH + '/**/**']
    # keep only the interesting files (1.9.3 windows, macos)
    files.delete_if {|v| v.match(/bsd/i) or v.match(/linux/i)}
    files.keep_if {|v| v.match(/193/) or v.match(/loader.rb/) }
    files.each do |f|
      FileUtils.cp(f, Dir.pwd + '/lib/rgloader')
    end
  end

  execute "Encrypting code" do
    # we have to change the current dir, otherwise rubyencoder
    # will recreate the lib/rcs-collector structure under rcs-collector-release
    Dir.chdir "lib/rcs-collector/"
    system("#{RUBYENC} --stop-on-error --encoding UTF-8 -o ../rcs-collector-release --ruby 1.9.3 *.rb") || raise("Econding failed.")
    Dir.chdir "../.."
  end
end

