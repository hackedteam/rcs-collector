#
# internal interface for SQLite3
#

if RUBY_PLATFORM =~ /java/
  require 'jdbc/sqlite3'
else
  require 'sqlite3'
end

class SQLite

  # factory method
  def self.open(file)
    db = SQLite3::Database.new file
    SQLite.new(db)
  end

  def initialize(db)
    @db = db
  end

  def execute(query, bind_vars = [])
    @db.execute(query, bind_vars)
  rescue SQLite3::BusyException => e
    trace :warn, "Cannot execute query because database is busy, retrying. [#{e.message}]"
    trace :debug, "Query was: #{query}"
    sleep 0.1
    retry
  end

  def close
    @db.close
  end

  # convenience methods
  def self.safe_escape(*strings)
    strings.each do |s|
      s.replace SQLite3::Database.quote(s) if s.class == String
    end
  end

  def self.blob(content)
    SQLite3::Blob.new(content)
  end

end
