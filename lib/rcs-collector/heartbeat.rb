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
    DB.instance.check_conn if not DB.instance.connected?
    
    # retrieve how many session we have
    # this number represents the number of backdoor that are synchronizing
    active_sessions = SessionManager.instance.how_many

    # default message
    message = "Idle..."

    # if we are serving backdoors, report it accordingly
    message = "Serving #{active_sessions} sessions" if active_sessions > 0

    # send my status to the db
    DB.instance.update_status message

  end
end

end #Collector::
end #RCS::