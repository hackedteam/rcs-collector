#
#  Event handlers
#

# relatives
require_relative 'heartbeat'
require_relative 'statistics'

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
    EM.epoll
    EM.threadpool_size = 10

    EM::run do
      EM.defer { EvidenceTransfer.run }

      # calculate and save the stats
      EM::PeriodicTimer.new(60) { EM.defer { StatsManager.instance.calculate } }

      # send the first heartbeat to the db, we are alive and want to notify the db immediately
      # subsequent heartbeats will be sent every HB_INTERVAL
      EM.defer { HeartBeat.perform }

      # set up the heartbeat (the interval is in the config)
      EM::PeriodicTimer.new(Config.instance.global['HB_INTERVAL']) { EM.defer { HeartBeat.perform } }
    end
  end
end #Events

end #Collector::
end #RCS::
