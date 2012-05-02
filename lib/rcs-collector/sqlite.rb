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
    def safe_escape(*strings)
      strings.each do |s|
        s.replace SQLite3::Database.quote(s) if s.class == String
      end
    end

    def blob(content)
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

=begin
  -7	BIT
  -6	TINYINT
  -5	BIGINT
  -4	LONGVARBINARY
  -3	VARBINARY
  -2	BINARY
  -1	LONGVARCHAR
  0	NULL
  1	CHAR
  2	NUMERIC
  3	DECIMAL
  4	INTEGER
  5	SMALLINT
  6	FLOAT
  7	REAL
  8	DOUBLE
  12	VARCHAR
  91	DATE
  92	TIME
  93	TIMESTAMP
  1111 	OTHER
=end

  INTEGER = 4
  VARCHAR = 12

  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    # factory method
    def open(file)
      #initialize the driver
      org.sqlite.JDBC
      db = java.sql.DriverManager.getConnection("jdbc:sqlite:#{file}")
      self.new(db)
    end

    # convenience methods
    def safe_escape(*strings)
      strings.each do |s|
        s.gsub!( /'/, "''" ) if s.class == String
      end
    end

    def blob(content)
      #TODO: implement this
    end
  end

  def initialize(db)
    @db = db
    @result_as_hash = false
  end

  def execute(query, bind_vars = [])
    statement = @db.createStatement
    result = []

    # we have to differentiate on the type of query
    if query =~ /SELECT/i
      execute_select statement, query, result
    elsif query =~ /\?/
      execute_insert_blob statement, query, bind_vars, result
    else
      result << statement.execute(query)
    end

  ensure
    statement.close
    return result
  end

  def close
    @db.close
  end

  def results_as_hash=(value)
    @result_as_hash = value
  end

  private

  def execute_select(statement, query, result)
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
          else
            raise "unsupported column type: #{type}"
        end

        if @result_as_hash
          row[meta.getColumnLabel(i)] = value
        else
          row << value
        end
      end

      result << row
    end
    res.close
  end

  def execute_insert_blob(statement, query, bind_vars, result)
    puts "PREPARED: #{query}"

    bind_vars.each do |var|
      puts var.inspect
    end

  end

end



class SQLite
  if RUBY_PLATFORM =~ /java/
    include SQLite_Java
  else
    include SQLite_Ruby
  end
end