require 'rcs-common/trace'
require 'rcs-common/winfirewall'

module RCS
  module Collector
    module Firewall
      extend self
      extend RCS::Tracer

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

        trace(:debug, "Creating default firewall rules...")

        # open_port_80 etc.
      end
    end
  end
end
