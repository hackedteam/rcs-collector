#
#  Event handlers
#

# relatives
require_relative 'heartbeat'
#require_relative 'statistics'

# from RCS::Common
require 'rcs-common/trace'
require 'rcs-common/systemstatus'

# system
require 'eventmachine'

module RCS
module Carrier

class Events
  include RCS::Tracer
  
  def setup

    # main EventMachine loop
    begin
      # all the events are handled here
      EM::run do
        # if we have epoll(), prefer it over select()
        EM.epoll

        # we are alive and ready to party
        SystemStatus.my_status = SystemStatus::OK

        # send the first heartbeat to the db, we are alive and want to notify the db immediately
        # subsequent heartbeats will be sent every HB_INTERVAL
        HeartBeat.perform

        # set up the heartbeat (the interval is in the config)
        EM::PeriodicTimer.new(Config.instance.global['HB_INTERVAL']) { EM.defer(proc{ HeartBeat.perform }) }

      end
    rescue Exception => e
      raise
    end

  end

end #Events

end #Collector::
end #RCS::

