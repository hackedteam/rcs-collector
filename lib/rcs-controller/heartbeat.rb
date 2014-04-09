require 'rcs-common/trace'
require 'rcs-common/systemstatus'
require 'rcs-common/heartbeat'

module RCS
  module Controller
    class HeartBeat < RCS::HeartBeat::Base
      component :controller

      before_heartbeat do
        # if the database connection has gone
        # try to re-login to the database again
        unless DB.instance.connected?
          trace :debug, "heartbeat: try to reconnect to rcs-db"
          DB.instance.connect!(:controller)
        end

        # still no luck ?  return and wait for the next iteration
        DB.instance.connected?
      end

      def status
        super
        #EvidenceTransfer.instance.status ? 'ERROR' : super
      end

      def message
        "Idle..."
      end
    end
  end
end
