#
#  Heartbeat to update the status of the component in the db
#

# relatives
require_relative 'sessions.rb'
require_relative 'status.rb'

# from RCS::Common
require 'rcs-common/trace'


module RCS
module Collector

class HeartBeat
  extend RCS::Tracer

  def self.perform

    # if the database connection has gone
    # try to re-login to the database again
    DB.instance.connect! if not DB.instance.connected?

    # still no luck ?  return and wait for the next iteration 
    return unless DB.instance.connected?

    # report our status to the db
    component = "RCS::Collector"
    # used only by NC
    ip = ''

    # retrieve how many session we have
    # this number represents the number of backdoor that are synchronizing
    active_sessions = SessionManager.instance.length

    # if we are serving backdoors, report it accordingly
    message = (active_sessions > 0) ? "Serving #{active_sessions} sessions" : "Idle..."

    # report our status
    status = Status.my_status
    disk = Status.disk_free
    cpu = Status.cpu_load
    pcpu = Status.my_cpu_load

    # create the stats hash
    stats = {:disk => disk, :cpu => cpu, :pcpu => pcpu}

    # send the status to the db
    DB.instance.update_status component, ip, status, message, stats

  end
end

end #Collector::
end #RCS::