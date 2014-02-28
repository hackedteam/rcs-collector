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

def encode(component)
  execute "Encrypting code for #{component}" do
    # we have to change the current dir, otherwise rubyencoder
    # will recreate the lib/rcs-collector structure under rcs-collector-release
    Dir.chdir "lib/rcs-#{component}/"
    system("#{RUBYENC} --stop-on-error --encoding UTF-8 -o ../rcs-#{component}-release --ruby 2.0.0 *.rb") || raise("Econding failed.")
    Dir.chdir "../.."
  end
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
    Dir[Dir.pwd + '/lib/rcs-carrier-release/*'].each do |f|
      File.delete(f) unless File.directory?(f)
    end
    Dir[Dir.pwd + '/lib/rcs-controller-release/*'].each do |f|
      File.delete(f) unless File.directory?(f)
    end
    Dir[Dir.pwd + '/lib/rgloader/*'].each do |f|
      File.delete(f) unless File.directory?(f)
    end
    Dir.delete(Dir.pwd + '/lib/rgloader') if File.exist?(Dir.pwd + '/lib/rgloader')
    Dir.delete(Dir.pwd + '/lib/rcs-collector-release') if File.exist?(Dir.pwd + '/lib/rcs-collector-release')
    Dir.delete(Dir.pwd + '/lib/rcs-carrier-release') if File.exist?(Dir.pwd + '/lib/rcs-carrier-release')
    Dir.delete(Dir.pwd + '/lib/rcs-controller-release') if File.exist?(Dir.pwd + '/lib/rcs-controller-release')
  end
end

case RbConfig::CONFIG['host_os']
  when /darwin/
    RUBYENCPATH = '/Applications/Development/RubyEncoder.app/Contents/MacOS'
    RUBYENC = "#{RUBYENCPATH}/rgencoder"
  when /mingw/
    RUBYENCPATH = 'C:/Program Files (x86)/RubyEncoder'
    RUBYENC = "\"C:\\Program Files (x86)\\RubyEncoder\\rgencoder.exe\""
end

desc "Create the encrypted code for release"
task :protect do
  Rake::Task[:unprotect].invoke
  execute "Creating release folder" do
    Dir.mkdir(Dir.pwd + '/lib/rcs-collector-release') if not File.directory?(Dir.pwd + '/lib/rcs-collector-release')
    Dir.mkdir(Dir.pwd + '/lib/rcs-carrier-release') if not File.directory?(Dir.pwd + '/lib/rcs-carrier-release')
    Dir.mkdir(Dir.pwd + '/lib/rcs-controller-release') if not File.directory?(Dir.pwd + '/lib/rcs-controller-release')
  end

  execute "Copying the rgloader" do
    RGPATH = RUBYENCPATH + '/Loaders'
    Dir.mkdir(Dir.pwd + '/lib/rgloader')
    files = Dir[RGPATH + '/**/**']
    # keep only the interesting files (2.0.x windows, macos)
    files.delete_if {|v| v.match(/bsd/i) or v.match(/linux/i)}
    files.keep_if {|v| v.match(/20/) or v.match(/loader.rb/) }
    files.each do |f|
      FileUtils.cp(f, Dir.pwd + '/lib/rgloader')
    end
  end

  encode('collector')
  encode('carrier')
  encode('controller')

end

require 'rcs-common/deploy'
ENV['DEPLOY_USER'] = 'Administrator'
ENV['DEPLOY_ADDRESS'] = '192.168.100.100'
RCS::Deploy::Task.import
