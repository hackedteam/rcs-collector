require 'rcs-common/trace'
require 'rcs-common/winfirewall'

module RCS
  module Collector
    module Firewall
      extend self
      extend RCS::Tracer

      RULE_PREFIX = "RCS_FWR_RULE_"

      def developer_machine?
        Config.instance.global['COLLECTOR_IS_GOOD']
      end

      def exists?
        WinFirewall.exists?
      end

      def disabled?
        exists? and (WinFirewall.status == :off)
      end

      def create_default_rules
        return unless exists?

        # Do nothing in this case
        return if developer_machine? and disabled?

        trace(:info, "Creating default firewall rules...")

        rule_name = "#{RULE_PREFIX}coll_to_first_anonym"
        port = Config.instance.global['LISTENING_PORT']
        # TODO: use the addr of the first anonymizer
        addr = :any
        WinFirewall.del_rule(rule_name)
        WinFirewall.add_rule(action: :allow, direction: :in, name: rule_name, local_port: port, remote_ip: addr, protocol: :tcp)

        rule_name = "#{RULE_PREFIX}coll_to_db"
        port = Config.instance.global['DB_PORT']
        addr = Config.instance.global['DB_ADDRESS']
        WinFirewall.del_rule(rule_name)
        WinFirewall.add_rule(action: :allow, direction: :out, name: rule_name, remote_port: port, remote_ip: addr, protocol: :tcp)
      end
    end
  end
end
