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

  def execute(query, bind_vars = [], *args)
    @db.execute(query, bind_vars, args)
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
      content
    end
  end

  def initialize(db)
    @db = db
    @result_as_hash = false
  end

  def execute(query, bind_vars = [], *args)
    result = []

    # we have to differentiate on the type of query
    if query =~ /SELECT/i
      execute_select query, result
    elsif query =~ /\?/
      execute_insert_blob query, bind_vars, *args, result
    else
      statement = @db.createStatement()
      result << statement.execute(query)
      statement.close()
    end

    return result
  end

  def close
    @db.close
  end

  def results_as_hash=(value)
    @result_as_hash = value
  end

  private

  def execute_select(query, result)
    statement = @db.createStatement()
    res = statement.executeQuery(query)
    meta = res.getMetaData()

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
          when 2004
            value = String.from_java_bytes(res.getBytes(i))
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
  ensure
    statement.close()
  end

  def execute_insert_blob(query, bind_vars, *args, result)
    statement = @db.prepareStatement(query)

    bind_vars = [bind_vars] + args

    begin

    bind_vars.each_with_index do |var, index|
      # len = var.bytesize
      # byte[] data = new byte[len]
      # Arrays.copyArray(...)

      data = var.to_java_bytes
      #puts "DATA SIZE: #{data.size}"
      statement.setBytes(index + 1, data)

      #statement.setString(index + 1, var)
    end

    rescue Exception => e
      puts "EXCEPTION: #{e.message}"
    end


    statement.executeUpdate()

  ensure
    statement.close()
  end

end



class SQLite
  if RUBY_PLATFORM =~ /java/
    include SQLite_Java
  else
    include SQLite_Ruby
  end
end


if __FILE__ == $0

  require 'fileutils'
  require 'securerandom'

  CACHE_FILE = './zzz_sqlite3'

  FileUtils.rm_rf CACHE_FILE

  db = SQLite.open CACHE_FILE
  schema = ["CREATE TABLE string (text CHAR(32))",
            "CREATE TABLE int (id CHAR(32), uid INT)",
            "CREATE TABLE bin (id CHAR(32), content BLOB)",
           ]
  # create all the tables
  schema.each do |query|
    db.execute query
  end
  db.close

  db = SQLite.open CACHE_FILE
  string = "ciao miao bau"
  db.execute("INSERT INTO string VALUES ('#{string}');")
  row = db.execute("SELECT text FROM string;")
  signature = row.first.first
  raise "string not equal" if signature != string
  db.close

  db = SQLite.open CACHE_FILE
  num = 123
  db.execute("INSERT INTO int VALUES (1, #{num});")
  row = db.execute("SELECT * FROM int;").first
  raise "int not equal" if row != ["1", 123]
  db.close

  db = SQLite.open CACHE_FILE
  blob = SecureRandom.random_bytes(10)

  puts blob.encoding
  puts blob.unpack('H*')

  db.execute("INSERT INTO bin VALUES (1, ?);", SQLite.blob(blob))

  content = db.execute("SELECT content FROM bin;").first

  puts content.first.encoding
  puts content.first.unpack('H*')
  raise "content not equal" if blob != content.first

  row = db.execute("SELECT * FROM bin;").first

  puts row[1].encoding
  puts row[1].unpack('H*')
  raise "content not equal" if blob != row[1]

  db.close



end