require 'helper'
require 'rcs-collector/cache.rb'

module RCS
module Collector

class TestRcsCache < Test::Unit::TestCase

  # dirty hack to fake the trace function
  class RCS::Collector::Cache
    def self.trace(a, b)
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

end

end #Collector::
end #RCS::
