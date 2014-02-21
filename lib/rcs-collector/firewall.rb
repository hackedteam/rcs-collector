require 'rcs-common/trace'
require 'rcs-common/winfirewall'

module RCS
  module Collector
    module Firewall
      extend self
      extend RCS::Tracer

      RULE_PREFIX = "RCS_FWC"

      def ok?
        !error_message
      end

      def error_message
        return nil if !WinFirewall.exists?
        return nil if developer_machine?
        return "Firewall must be activated on all profiles" if WinFirewall.status == :off
        return "Firewall default policy must block incoming connections by default" if !WinFirewall.block_inbound?
        return "The anonymizers chain is not configured" if !first_anonymizer_address
        nil
      end

      def create_default_rules
        return if !WinFirewall.exists?

        trace(:info, "Creating default firewall rules...")

        # Delete legacy rules
        WinFirewall.del_rule("RCS Collector")

        # Create the default rules
        rule_name = "#{RULE_PREFIX} First Anonymizer to Collector"
        WinFirewall.del_rule(rule_name)
        port = Config.instance.global['LISTENING_PORT']
        addr = first_anonymizer_address
        @last_anonymizer_address = addr
        raise "The first anonymizer address is unknown!" if !addr
        WinFirewall.add_rule(action: :allow, direction: :in, name: rule_name, local_port: port, remote_ip: addr, protocol: :tcp)

        rule_name = "#{RULE_PREFIX} Master to Collector"
        WinFirewall.del_rule(rule_name)
        port = Config.instance.global['LISTENING_PORT']
        addr = Config.instance.global['DB_ADDRESS']
        WinFirewall.add_rule(action: :allow, direction: :in, name: rule_name, remote_port: :any, local_port: port, remote_ip: addr, protocol: :tcp)
      end

      def first_anonymizer_changed?
        return false if developer_machine?
        first_anonymizer_address != @last_anonymizer_address
      end

      private

      def first_anonymizer_address
        developer_machine? ? :any : DB.instance.first_anonymizer['address']
      end

      def developer_machine?
        Config.instance.global['COLLECTOR_IS_GOOD']
      end
    end
  end
end
