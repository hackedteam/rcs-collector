#
#  Configuration parsing module
#

# from RCS::Common
require 'rcs-common/trace'
require 'rcs-common/flatsingleton'

# system
require 'yaml'
require 'pp'
require 'optparse'

module RCS
module Collector

class Config
  include Singleton
  extend FlatSingleton
  include Tracer

  CONF_FILE = '/config/config.yaml'

  DEFAULT_CONFIG= {'DB_ADDRESS' => 'rcs-server',
                   'DB_PORT' => 4443,
                   'DB_CERT' => 'rcs-ca.pem',
                   'DB_SIGN' => 'rcs-server.sig',
                   'LISTENING_PORT' => 80,
                   'HB_INTERVAL' => 30,
                   'NC_INTERVAL' => 30,
                   'NC_ENABLED' => true,
                   'COLL_ENABLED' => true}

  attr_reader :global

  def initialize
    @global = {}
  end

  def load_from_file
    trace :info, "Loading configuration file..."
    conf_file = Dir.pwd + CONF_FILE

    # load the config in the @global hash
    begin
      File.open(conf_file, "r") do |f|
        @global = YAML.load(f.read)
      end
    rescue
      trace :fatal, "Cannot open config file [#{conf_file}]"
      return false
    end

    if not @global['DB_CERT'].nil? then
      if not File.exist?(Dir.pwd + "/config/" + @global['DB_CERT']) then
        trace :fatal, "Cannot open certificate file [#{@global['DB_CERT']}]"
        return false
      end
    end

    if not @global['DB_SIGN'].nil? then
      if not File.exist?(Dir.pwd + "/config/" + @global['DB_SIGN']) then
        trace :fatal, "Cannot open signature file [#{@global['DB_SIGN']}]"
        return false
      end
    end

    # to avoid problems with checks too frequent
    if (@global['HB_INTERVAL'] and @global['HB_INTERVAL'] < 10) or (@global['NC_INTERVAL'] and @global['NC_INTERVAL'] < 10) then
      trace :fatal, "Interval too short, please increase it"
      return false
    end

    return true
  end

  def safe_to_file
    trace :info, "Writing configuration file..."
    conf_file = Dir.pwd + CONF_FILE

    # Write the @global into a yaml file
    begin
      File.open(conf_file, "w") do |f|
        f.write(@global.to_yaml)
      end
    rescue
      trace :fatal, "Cannot write config file [#{conf_file}]"
      return false
    end

    return true
  end

  def run(options)
    # load the current config
    load_from_file

    trace :info, "Current configuration:"
    pp @global

    # use the default values
    if options[:defaults] then
      @global = DEFAULT_CONFIG
    end

    # values taken from command line
    @global['DB_ADDRESS'] = options[:db_address] unless options[:db_address].nil?
    @global['DB_PORT'] = options[:db_port] unless options[:db_port].nil?
    @global['DB_CERT'] = options[:db_cert] unless options[:db_cert].nil?
    @global['DB_SIGN'] = options[:db_sign] unless options[:db_sign].nil?
    @global['LISTENING_PORT'] = options[:port] unless options[:port].nil?
    @global['HB_INTERVAL'] = options[:hb_interval] unless options[:hb_interval].nil?
    @global['NC_INTERVAL'] = options[:nc_interval] unless options[:nc_interval].nil?
    @global['NC_ENABLED'] = options[:nc_enabled] unless options[:nc_enabled].nil?
    @global['COLL_ENABLED'] = options[:coll_enabled] unless options[:coll_enabled].nil?

    trace :info, "Final configuration:"
    pp @global

    # save the configuration
    safe_to_file

    return 0
  end

  # executed from rcs-collector-config
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
      # Set a banner, displayed at the top of the help screen.
      opts.banner = "Usage: rcs-collector-config [options]"

      # Define the options, and what they do
      opts.on( '-l', '--listen PORT', Integer, 'Listen on tcp/PORT' ) do |port|
        options[:port] = port
      end
      opts.on( '-a', '--db-address HOST', String, 'Use the rcs-db at HOST' ) do |host|
        options[:db_address] = host
      end
      opts.on( '-p', '--db-port PORT', Integer, 'Connect to tcp/PORT on rcs-db' ) do |port|
        options[:db_port] = port
      end
      opts.on( '-t', '--db-cert FILE', 'The certificate file (pem) used for ssl communication with rcs-db' ) do |file|
        options[:db_cert] = file
      end
      opts.on( '-s', '--db-sign FILE', 'The signature file (sig) used for authentication with rcs-db' ) do |file|
        options[:db_sign] = file
      end
      opts.on( '-b', '--db-heartbeat SEC', Integer, 'Time in seconds between two heartbeats to the rcs-db' ) do |sec|
        options[:hb_interval] = sec
      end
      opts.on( '-H', '--nc-heartbeat SEC', Integer, 'Time in seconds between two heartbeats to the network components' ) do |sec|
        options[:nc_interval] = sec
      end
      opts.on( '-n', '--network', 'Enable the Network Controller' ) do
        options[:nc_enabled] = true
      end
      opts.on( '-N', '--no-network', 'Disable the Network Controller' ) do
        options[:nc_enabled] = false
      end
      opts.on( '-c', '--collector', 'Enable the Backdoor Collector' ) do
        options[:coll_enabled] = true
      end
      opts.on( '-C', '--no-collector', 'Disable the Backdoor Collector' ) do
        options[:coll_enabled] = false
      end
      opts.on( '-X', '--defaults', 'Write a new config file with default values' ) do
        options[:defaults] = true
      end

      # This displays the help screen
      opts.on( '-h', '--help', 'Display this screen' ) do
        puts opts
        return 0
      end
    end

    optparse.parse(argv)

    # execute the configurator
    return Config.run(options)
  end

end #Config
end #Collector::
end #RCS::