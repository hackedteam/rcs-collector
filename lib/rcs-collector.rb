# ensure the working dir is correct
Dir.chdir File.dirname(File.dirname(File.realpath(__FILE__)))

# release file are encrypted and stored in a different directory
if File.directory?(Dir.pwd + '/lib/rcs-collector-release')
  require_relative 'rcs-collector-release/collector.rb'
# otherwise we are using development code
elsif File.directory?(Dir.pwd + '/lib/rcs-collector')
  puts "WARNING: Executing clear text code... (debug only)"
  require_relative 'rcs-collector/collector.rb'
else
  puts "FATAL: cannot find any rcs-collector code!"
end


