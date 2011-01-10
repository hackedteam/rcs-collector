require 'helper'
require 'rcs-collector/cache.rb'

module RCS
module Collector

class TestRcsCache < Test::Unit::TestCase

  # dirty hack to fake the trace function
  class RCS::Collector::Cache
    def self.trace(a, b)
      puts b
    end
  end

  # Called before every test method runs. Can be used
  # to set up fixture information.
  def setup
    Cache.destroy!
    assert_false File.exist?(Dir.pwd + "/config/cache.db")
  end

  # Called after every test method runs. Can be used to tear
  # down fixture information.
  def teardown
    Cache.destroy!
  end

  def test_private_method
    # create! is a private method, nobody should call it
    assert_raise NoMethodError do
      Cache.create!
    end
  end

  def test_empty!
    # this should create the cache from scratch
    Cache.empty!

    # check if the file was created
    assert_true File.exist?(Dir.pwd + "/config/cache.db")
  end

  def test_zero_length
    # not existent should return always zero
    assert_equal 0, Cache.length

    Cache.empty!
    # empty (but initialized) cache
    assert_equal 0, Cache.length
  end

  def test_signature
    # since the cache is not initialized,
    # the call should create it and store the value
    Cache.signature = "test signature"

    # check if the file was created
    assert_true File.exist?(Dir.pwd + "/config/cache.db")

    # check the correct value
    assert_equal "test signature", Cache.signature
  end

  def test_empty_init
    # clear the cache
    Cache.empty!

    assert_nil Cache.signature
    assert_equal 0, Cache.length
  end

  def test_class_keys
    entries = {'BUILD001' => 'secret class key', 'BUILD002' => "another secret"}
    entry = {'BUILD003' => 'top secret'}

    # since the cache is not initialized,
    # the call should create it and store the value
    Cache.add_class_keys entries
    Cache.add_class_keys entry

    # check if the file was created
    assert_true File.exist?(Dir.pwd + "/config/cache.db")

    # we have added 3 elements
    assert_equal 3, Cache.length

    # check the correct values
    assert_equal "top secret", Cache.class_keys['BUILD003']
    assert_equal "another secret", Cache.class_keys['BUILD002']
    assert_equal "secret class key", Cache.class_keys['BUILD001']
  end

  def test_config
    # random ids
    bid = SecureRandom.random_number(1024)
    cid = SecureRandom.random_number(1024)
    # random binary bytes for the config
    config = SecureRandom.random_bytes(1024)
    
    # not yet in cache
    assert_false Cache.new_conf? bid

    # save a config in the cache
    Cache.save_conf(bid, cid, config)

    # should be in cache
    assert_true Cache.new_conf? bid
    # the bid - 1 does not exist in cache
    assert_false Cache.new_conf? bid - 1

    # retrieve the config
    ccid, cconfig = Cache.new_conf bid

    assert_equal cid, ccid
    assert_equal config, cconfig
    
    # delete the config
    Cache.del_conf bid
    assert_false Cache.new_conf? bid
  end

  def test_download
    # random ids
    bid = SecureRandom.random_number(1024)
    d1 = SecureRandom.random_number(1024)
    d2 = SecureRandom.random_number(1024)
    # random string for the download
    filename1 = SecureRandom.base64(100)
    filename2 = SecureRandom.base64(100)

    # not yet in cache
    assert_false Cache.new_downloads? bid

    downloads = {d1 => filename1, d2 => filename2}

    # save a config in the cache
    Cache.save_downloads(bid, downloads)

    # should be in cache
    assert_true Cache.new_downloads? bid
    # the bid - 1 does not exist in cache
    assert_false Cache.new_downloads? bid - 1

    # retrieve the config
    cdown = Cache.new_downloads bid

    assert_equal downloads[d1], cdown[d1]
    assert_equal downloads[d2], cdown[d2]

    # delete the config
    Cache.del_downloads bid
    assert_false Cache.new_downloads? bid
  end

  def test_filesystem
    # random ids
    bid = SecureRandom.random_number(1024)
    f1 = SecureRandom.random_number(1024)
    f2 = SecureRandom.random_number(1024)
    # random string for the download
    filename1 = SecureRandom.base64(100)
    filename2 = SecureRandom.base64(100)

    # not yet in cache
    assert_false Cache.new_filesystems? bid

    filesystems = {f1 => {:depth => 1, :path => filename1},
                   f2 => {:depth => 2, :path => filename2}}

    # save a config in the cache
    Cache.save_filesystems(bid, filesystems)

    # should be in cache
    assert_true Cache.new_filesystems? bid
    # the bid - 1 does not exist in cache
    assert_false Cache.new_filesystems? bid - 1

    # retrieve the config
    cfiles = Cache.new_filesystems bid

    assert_equal filesystems[f1], cfiles[f1]
    assert_equal filesystems[f2], cfiles[f2]

    # delete the config
    Cache.del_filesystems bid
    assert_false Cache.new_filesystems? bid
  end

end

end #Collector::
end #RCS::
