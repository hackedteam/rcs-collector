#
# internal interface for SQLite3
#

if RUBY_PLATFORM =~ /java/
  require 'java'
  require 'jdbc/sqlite3'
else
  require 'sqlite3'
end


# implementation for MRI ruby
module SQLite_Ruby

  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    # factory method
    def open(file)
      db = SQLite3::Database.new file
      self.new(db)
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

  def results_as_hash=(value)
    @db.results_as_hash = value
  end

end

# implementation for JRuby (java)
module SQLite_Java

  CHAR = 1
  INTEGER = 4
  VARCHAR = 12
  DATE = 91
  TIME = 92
  TIMESTAMP = 93

  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    # factory method
    def open(file)
      #initialize the driver
      org.sqlite.JDBC
      #grab your connection
      db = java.sql.DriverManager.getConnection("jdbc:sqlite:#{file}")
      self.new(db)
    end

    # convenience methods
    def self.safe_escape(*strings)
    end

    def self.blob(content)
    end
  end

  def initialize(db)
    @db = db
    @result_as_hash = false
  end

  def execute(query, bind_vars = [])
    statement = @db.createStatement
    flat = []

    # we have to differentiate on the type of query
    if query =~ /SELECT/i

      res = statement.executeQuery(query)
      meta = res.getMetaData

      while (res.next)
        row = @result_as_hash ? {} : []

        # inspect the columns (starting from 1... java)
        1.upto(meta.getColumnCount) do |i|

          type = meta.getColumnType(i)
          case type
            when VARCHAR
              value = res.getString(i)
            when INTEGER
              value = res.getInt(i)
          end

          if @result_as_hash
            row[meta.getColumnLabel(i)] = value
          else
            row << value
          end
        end

        flat << row
      end
      res.close

    else
      # save the result in the flat array
      flat << statement.execute(query)
    end

  ensure
    statement.close
    return flat
  end

  def close
    @db.close
  end

  def results_as_hash=(value)
    @result_as_hash = value
  end

end



class SQLite
  if RUBY_PLATFORM =~ /java/
    include SQLite_Java
  else
    include SQLite_Ruby
  end
end