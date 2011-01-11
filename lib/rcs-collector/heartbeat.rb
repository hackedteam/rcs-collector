#
#  Heartbeat to update the status of the component in the db
#

# relatives
require_relative 'sessions.rb'

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


    # report our status to the db
    component = "RCS::Collector"
    # used only by NC
    ip = ''

    # retrieve how many session we have
    # this number represents the number of backdoor that are synchronizing
    active_sessions = SessionManager.instance.length

    # if we are serving backdoors, report it accordingly
    message = (active_sessions > 0) ? "Serving #{active_sessions} sessions" : "Idle..."

    # everything ok for us...
    #TODO: set it accordingly
    status = "OK"

    #TODO: implement these metrics (ARGH!!)
    disk = 0
    cpu = 0
    pcpu = 0

    # create the stats hash
    stats = {:disk => disk, :cpu => cpu, :pcpu => pcpu}

    # send the status to the db
    DB.instance.update_status component, ip, status, message, stats

  end
end

end #Collector::
end #RCS::