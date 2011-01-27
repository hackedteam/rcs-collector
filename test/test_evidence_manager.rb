require 'helper'

module RCS
module Collector

# dirty hack to fake the trace function
# re-open the class and override the method
class EvidenceManager
  def trace(a, b)
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

class TestEvidenceManager < Test::Unit::TestCase

  def setup
    EvidenceManager.instance.create_repository "TEST-INSTANCE"
    assert_true File.exist?(EvidenceManager::REPO_DIR + '/TEST-INSTANCE')
  end

  def teardown
    File.delete(EvidenceManager::REPO_DIR + '/TEST-INSTANCE')
  end

  def test_sync_start

    session = {:bid => 0,
               :build => 'test-build',
               :instance => 'test-instance',
               :subtype => 'test-subtype'}
    
    EvidenceManager.instance.sync_start session, 2011010101, 'test-user', 'test-device', 'test-source', Time.now

    
  end


end

end #Collector::
end #RCS::
