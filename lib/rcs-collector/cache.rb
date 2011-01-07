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
              "INSERT INTO signature VALUES ('no signature')",  # insert a fake value to be updated later
              "CREATE TABLE class_keys (id CHAR(16), key CHAR(32))"]

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

  def self.signature=(sig)
    # ensure the db was already created, otherwise create it
    create! unless File.exist?(CACHE_FILE)

    begin
      db = SQLite3::Database.open CACHE_FILE
      db.execute("UPDATE signature SET signature = '#{sig}';")
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
      trace :warn, "Cannot save the cache: #{e.message}"
    end

    return class_keys
  end

end #Cache

end #Collector::
end #RCS::