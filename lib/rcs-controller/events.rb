require 'rcs-common/trace'
require 'rcs-common/systemstatus'

require_relative 'network'

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
          SystemStatus.my_status = SystemStatus::OK

          EM::PeriodicTimer.new(check_interval) { Network.check }
        end
      end
    end
  end
end
