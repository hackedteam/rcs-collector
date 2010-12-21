#
#  The main file of the collector
#

# relatives
require_relative 'events.rb'

# from RCS::Common
require 'rcs-common/trace'

# from System
require 'yaml'

module RCS
module Collector

class Application
  include Tracer

  # the main of the collector
  def run(options)

    # if we can't find the trace config file, default to the system one
    if File.exist?('trace.yaml') then
      typ = Dir.pwd
      ty = 'trace.yaml'
    else
      typ = File.dirname(File.dirname(File.dirname(__FILE__))) + "/bin"
      ty = typ + "/trace.yaml"
      puts "Cannot find 'trace.yaml' using the default one (#{ty})"
    end

    # initialize the tracing facility
    begin
      trace_init typ, ty
    rescue Exception => e
      puts e
      exit
    end

    begin

      #TODO: config file parsing

      #TODO: cache cleanup

      #TODO: test db connection

      #TODO: main loop
      Events.new.setup 8080

    rescue Exception => detail
      trace :fatal, "FAILURE: " << detail.message
      trace :fatal, "EXCEPTION: " << detail.backtrace.join("\n")
      return 1
    end

    return 0
  end

  # since we cannot use trace from a class method
  # we instantiate here an object and run it
  def self.run!(*argv)
    return Application.new.run(argv)
  end

end # Application::
end # Collector::
end # RCS::


if __FILE__ == $0
  RCS::Collector::Application.run!(*ARGV)
end
