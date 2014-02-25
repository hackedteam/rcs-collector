require 'log4r'

require_relative 'sqlite'

module RCS
  module Collector
    class Migration

      attr_reader :logger, :version

      def initialize(**options)
        @version = options[:up_to] || File.read(Dir.pwd + '/config/VERSION')
        @logger = options[:logger] || default_logger
      end

      def default_logger
        Log4r::Logger.new("migration").tap { |logger| logger.add(Log4r::Outputter.stdout) }
      end

      def self.run(**options)
        new(options).run
      end

      def run
        logger.info("Migrating to #{version}")

        migrate_sqlite_scout_column if version >= '9.2.0'
      end


      # Migrations

      def migrate_sqlite_scout_column
        dbs_path = File.expand_path("../../../evidence", __FILE__)

        return unless Dir.exists?(dbs_path)

        Dir["#{dbs_path}/RCS_*"].each do |path|
          db = SQLite3::Database.new(path)
          schema = db.table_info(:info)

          # Skip if the info table is missing
          next if schema.empty?

          # Skip if the level column already exists or the scout column is missing
          next if !schema.find  { |column| column['name'] == 'scout' }
          next if schema.find  { |column| column['name'] == 'level' }

          logger.info("Migrating scout column of database #{File.basename(path)}")

          db.execute("ALTER TABLE info ADD COLUMN level CHAR(16)")
          db.execute("UPDATE info SET level = (CASE scout WHEN 1 THEN 'scout' ELSE 'elite' END)")

          logger.info("Done")
        end
      rescue Exception => ex
        logger.error("#{ex.class} #{ex.message} #{ex.backtrace}")
      end
    end
  end
end
