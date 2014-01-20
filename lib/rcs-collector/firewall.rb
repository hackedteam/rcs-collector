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

        # Delete legacy rules
        WinFirewall.del_rule("RCS Collector")
        WinFirewall.del_rule("RCS Database")

        WinFirewall.del_rule(/#{RULE_PREFIX}/)

        rule_name = "#{RULE_PREFIX}anonym_to_coll"
        port = Config.instance.global['LISTENING_PORT']
        addr = DBCache.first_anonymizer
        raise "The first anonymizer address is unknown!" if addr.blank? and !developer_machine?
        WinFirewall.add_rule(action: :allow, direction: :in, name: rule_name, local_port: port, remote_ip: addr, protocol: :tcp)

        rule_name = "#{RULE_PREFIX}db_to_coll"
        port = Config.instance.global['LISTENING_PORT']
        addr = Config.instance.global['DB_ADDRESS']
        WinFirewall.add_rule(action: :allow, direction: :in, name: rule_name, remote_port: port, remote_ip: addr, protocol: :tcp)
      end
    end
  end
end
