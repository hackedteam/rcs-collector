# save the execution dir
# useful during configuration to get filename paths
$invocation_directory = Dir.pwd
$invocation_directory = ENV['CWD'] if ENV['CWD']

# ensure the working dir is correct
$execution_directory = File.dirname(File.dirname(File.realpath(__FILE__)))
Dir.chdir $execution_directory

# release file are encrypted and stored in a different directory
if File.directory?(Dir.pwd + '/lib/rcs-carrier-release')
  require_relative 'rcs-carrier-release/carrier.rb'
# otherwise we are using development code
elsif File.directory?(Dir.pwd + '/lib/rcs-carrier')
  puts "WARNING: Executing clear text code... (debug only)"
  require_relative 'rcs-carrier/carrier.rb'
else
  puts "FATAL: cannot find any rcs-carrier code!"
end
