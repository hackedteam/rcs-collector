require 'fileutils'

def execute(message)
  print message + '...'
  STDOUT.flush
  if block_given?
    yield
  end
  puts ' ok'
end

def windows?
  RbConfig::CONFIG['host_os'] =~ /mingw/
end

def verbose?
  Rake.verbose == true
end
