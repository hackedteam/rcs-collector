require 'rcs-common/trace'
require 'rcs-common/systemstatus'
require 'rcs-common/heartbeat'

module RCS
  module Controller
    class HeartBeat < RCS::HeartBeat::Base
      component :controller

      def perform
        # if the database connection has gone
        # try to re-login to the database again
        unless DB.instance.connected?
          trace :debug, "heartbeat: try to reconnect to rcs-db"
          DB.instance.connect!(:controller)
        end

        # still no luck ? return and wait for the next iteration
        return unless DB.instance.connected?

        message = "Idle"

        return [OK, message]
      end

    end
  end
end
