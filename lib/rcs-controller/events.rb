#
#  Event handlers
#

# from RCS::Common
require 'rcs-common/trace'
require 'rcs-common/systemstatus'

require_relative 'network'

# system
require 'eventmachine'

module RCS
module Controller

class Events
  include RCS::Tracer
  
  def setup(port = 80)

    # main EventMachine loop
    begin
      # all the events are handled here
      EM::run do
        # if we have epoll(), prefer it over select()
        EM.epoll

        # we are alive and ready to party
        SystemStatus.my_status = SystemStatus::OK

        # first heartbeat and checks
        EM.defer(proc{ Network.check })
        # subsequent checks
        EM::PeriodicTimer.new(Config.instance.global['NC_INTERVAL']) { EM.defer(proc{ Network.check }) }

      end
    rescue Exception => e
      raise
    end

  end

end #Events

end #Collector::
end #RCS::

