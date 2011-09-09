#
#  Configuration parsing module
#

# from RCS::Common
require 'rcs-common/trace'

# system
require 'yaml'
require 'pp'
require 'optparse'
require 'net/http'

module RCS
module Collector

class Config
  include Singleton
  include Tracer

  CONF_DIR = 'config'
  CONF_FILE = 'config.yaml'

  DEFAULT_CONFIG= {'DB_ADDRESS' => 'rcs-server',
                   'DB_PORT' => 4444,
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
    conf_file = File.join Dir.pwd, CONF_DIR, CONF_FILE

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
      if not File.exist?(Config.instance.file('DB_CERT')) then
        trace :fatal, "Cannot open certificate file [#{@global['DB_CERT']}]"
        return false
      end
    end

    if not @global['DB_SIGN'].nil? then
      if not File.exist?(Config.instance.file('DB_SIGN')) then
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

  def file(name)
    return File.join Dir.pwd, CONF_DIR, @global[name]
  end

  def safe_to_file
    conf_file = File.join Dir.pwd, CONF_DIR, CONF_FILE

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

    trace :info, ""
    trace :info, "Current configuration:"
    pp @global

    # use the default values
    if options[:defaults] then
      @global = DEFAULT_CONFIG
    end

    # values taken from command line
    @global['DB_ADDRESS'] = options[:db_address] unless options[:db_address].nil?
    @global['DB_PORT'] = options[:db_port] unless options[:db_port].nil?
    @global['LISTENING_PORT'] = options[:port] unless options[:port].nil?
    @global['HB_INTERVAL'] = options[:hb_interval] unless options[:hb_interval].nil?
    @global['NC_INTERVAL'] = options[:nc_interval] unless options[:nc_interval].nil?
    @global['NC_ENABLED'] = options[:nc_enabled] unless options[:nc_enabled].nil?
    @global['COLL_ENABLED'] = options[:coll_enabled] unless options[:coll_enabled].nil?

    if options[:db_sign]
      sig = get_from_server options[:user], options[:pass], 'server'
      File.open(Config.instance.file('DB_SIGN'), 'wb') {|f| f.write sig}
    end

    if options[:db_cert]
      sig = get_from_server options[:user], options[:pass], 'cert'
      File.open(Config.instance.file('DB_CERT'), 'wb') {|f| f.write sig}
    end

    trace :info, ""
    trace :info, "Final configuration:"
    pp @global

    # save the configuration
    safe_to_file

    return 0
  end

  def get_from_server(user, pass, resource)
    begin
      http = Net::HTTP.new(@global['DB_ADDRESS'], 4444)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE

      # login
      account = {:user => user, :pass => pass }
      resp = http.request_post('/auth/login', account.to_json, nil)
      cookie = resp['Set-Cookie'] unless resp['Set-Cookie'].nil?

      # get the signature or the cert
      res = http.request_get("/signature/#{resource}", {'Cookie' => cookie})
      sig = JSON.parse(res.body)

      # logout
      http.request_post('/auth/logout', nil, {'Cookie' => cookie})
      return sig['value']
    rescue Exception => e
      trace :fatal, "ERROR: auto-retrieve of component failed: #{e.message}"
    end
    return nil
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
      opts.on( '-d', '--db-address HOSTNAME', 'Use the rcs-db at HOSTNAME' ) do |host|
        options[:db_address] = host
      end
      opts.on( '-P', '--db-port PORT', Integer, 'Connect to tcp/PORT on rcs-db' ) do |port|
        options[:db_port] = port
      end
      opts.on( '-t', '--db-cert', 'Retrieve the certificate file (pem) used from rcs-db (requires --user-pass)' ) do
        options[:db_cert] = true
      end
      opts.on( '-s', '--db-sign', 'Retrieve the signature file (sig) from rcs-db (requires --user-pass)' ) do
        options[:db_sign] = true
      end
      opts.on( '-u', '--user USERNAME', 'rcs-db username' ) do |user|
        options[:user] = user
      end
      opts.on( '-p', '--password PASSWORD', 'rcs-db password' ) do |password|
        options[:pass] = password
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

    if options[:db_sign]
      if options[:user].nil? or options[:pass].nil?
        puts "ERROR: You must specify --user-pass"
        return 1
      end
    end

    # execute the configurator
    return Config.instance.run(options)
  end

end #Config
end #Collector::
end #RCS::