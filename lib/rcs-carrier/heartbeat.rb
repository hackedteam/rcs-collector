#
#  Heartbeat to update the status of the component in the db
#

# from RCS::Common
require 'rcs-common/trace'
require 'rcs-common/systemstatus'

module RCS
module Carrier

class HeartBeat
  extend RCS::Tracer

  def self.perform
    # if the database connection has gone
    # try to re-login to the database again
    DB.instance.connect! if not DB.instance.connected?

    # still no luck ?  return and wait for the next iteration
    return unless DB.instance.connected?

    # report our status to the db
    component = "RCS::Carrier"

    # if we are serving agents, report it accordingly
    # TODO: report the number of repository
    #message = (active_sessions > 0) ? "Serving #{active_sessions} sessions" : "Idle..."
    message = "TODO..."

    # report our status
    status = SystemStatus.my_status
    disk = SystemStatus.disk_free
    cpu = SystemStatus.cpu_load
    pcpu = SystemStatus.my_cpu_load(component)

    # create the stats hash
    stats = {:disk => disk, :cpu => cpu, :pcpu => pcpu}

    # send the status to the db
    DB.instance.update_status component, '', status, message, stats, 'carrier', $version
  end
end

end #Collector::
end #RCS::