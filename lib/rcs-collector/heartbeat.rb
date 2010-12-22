#
#  Heartbeat to update the status of the component in the db
#

# from RCS::Common
require 'rcs-common/trace'

# system

module RCS
module Collector

class HeartBeat
  extend RCS::Tracer

  def self.perform
    #TODO: implement the real heartbeat
    trace :debug, "heartbeat: #{Time.now}"
  end
end

end #Collector::
end #RCS::