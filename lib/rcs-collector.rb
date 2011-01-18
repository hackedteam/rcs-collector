
# release file are encrypted and stored in a different directory
if File.directory?(Dir.pwd + '/lib/rcs-collector-release')
  require 'rcs-collector-release/collector.rb'
# otherwise we are using development code
elsif File.directory?(Dir.pwd + '/lib/rcs-collector')
  puts "WARNING: Executing clear text code... (debug only)"
  require 'rcs-collector/collector.rb'
else
  puts "FATAL: cannot find any rcs-collector code!"
end


