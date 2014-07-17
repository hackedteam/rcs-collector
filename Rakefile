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

def verbose?
  Rake.verbose == true
end

def exec_rubyencoder(cmd)
  if verbose?
    system(cmd) || raise("Econding failed.")
  else
    raise("Econding failed.") if `#{cmd}` =~ /[1-9]\serror/
  end
end

# Copy the bin folder to bin-release and encode it
# Note: The rcs-license-check script is used during the installation
def encode_bin
  execute "Encrypting code of the bin folder (use --trace to see RubyEncoder output)" do
    FileUtils.rm_rf("bin-release")
    FileUtils.cp_r("bin", "bin-release")

    Dir["bin-release/*"].each do |path|
      extname = File.extname(path).downcase
      is_ruby_script = (extname == ".rb") || (extname.empty? and File.read(path) =~ /\#\!.+ruby/i)
      next unless is_ruby_script
      exec_rubyencoder("#{RUBYENC} --stop-on-error --encoding UTF-8 -b- --ruby 2.0.0 #{path}")
    end
  end
end

def encode_lib(component)
  execute "Encrypting code for #{component} (use --trace to see RubyEncoder output)" do
    # we have to change the current dir, otherwise rubyencoder
    # will recreate the lib/rcs-collector structure under rcs-collector-release
    Dir.chdir "lib/rcs-#{component}/"
    exec_rubyencoder("#{RUBYENC} --stop-on-error --encoding UTF-8 -o ../rcs-#{component}-release --ruby 2.0.0 *.rb")
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
    FileUtils.rm_rf(Dir.pwd + '/rgloader') if File.exist?(Dir.pwd + '/rgloader')
    FileUtils.rm_rf(Dir.pwd + '/bin-release') if File.exist?(Dir.pwd + '/bin-release')
    FileUtils.rm_rf(Dir.pwd + '/lib/rcs-collector-release') if File.exist?(Dir.pwd + '/lib/rcs-collector-release')
    FileUtils.rm_rf(Dir.pwd + '/lib/rcs-carrier-release') if File.exist?(Dir.pwd + '/lib/rcs-carrier-release')
    FileUtils.rm_rf(Dir.pwd + '/lib/rcs-controller-release') if File.exist?(Dir.pwd + '/lib/rcs-controller-release')
  end
end

case RbConfig::CONFIG['host_os']
  when /darwin/
    paths = ['/Applications/Development/RubyEncoder.app/Contents/MacOS', '/Applications/RubyEncoder.app/Contents/MacOS']
    RUBYENCPATH = File.exists?(paths.first) ? paths.first : paths.last
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
    Dir.mkdir(Dir.pwd + '/rgloader')
    files = Dir[RGPATH + '/**/**']
    # keep only the interesting files (2.0.x windows, macos)
    files.delete_if {|v| v.match(/bsd/i) or v.match(/linux/i)}
    files.keep_if {|v| v.match(/20/) or v.match(/loader.rb/) }
    files.each do |f|
      FileUtils.cp(f, Dir.pwd + '/rgloader')
    end
  end

  encode_bin
  encode_lib('collector')
  encode_lib('carrier')
  encode_lib('controller')
end

if ARGV.find { |arg| arg.start_with?('deploy') } or ARGV.empty?
  require 'rcs-common/deploy'
  ENV['DEPLOY_USER'] = 'Administrator'
  ENV['DEPLOY_ADDRESS'] = '192.168.100.100'
  RCS::Deploy::Task.import
end
