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
                   'DB_PORT' => 443,
                   'DB_CERT' => 'rcs.pem',
                   'DB_SIGN' => 'rcs-server.sig',
                   'LISTENING_PORT' => 80,
                   'HB_INTERVAL' => 30,
                   'NC_INTERVAL' => 30,
                   'CHK_ANON_LISTENING_PORT' => 4499,
                   'RESOLVE_IP' => true,
                   'SSL_VERIFY' => true}

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

    unless @global['DB_CERT'].nil? then
      unless File.exist?(Config.instance.file('DB_CERT'))
        trace :fatal, "Cannot open certificate file [#{@global['DB_CERT']}]"
        return false
      end
    end

    unless @global['DB_SIGN'].nil? then
      unless File.exist?(Config.instance.file('DB_SIGN'))
        trace :fatal, "Cannot open signature file [#{@global['DB_SIGN']}]"
        return false
      end
    end

    # to avoid problems with checks too frequent
    if (@global['HB_INTERVAL'] and @global['HB_INTERVAL'] < 10) or (@global['NC_INTERVAL'] and @global['NC_INTERVAL'] < 10)
      trace :fatal, "Interval too short, please increase it"
      return false
    end

    @global['SSL_VERIFY'] = true if @global['SSL_VERIFY'].nil?

    return true
  end

  def file(name)
    return File.join Dir.pwd, CONF_DIR, @global[name].nil? ? name : @global[name]
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
    trace :info, "Previous configuration:"
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

    if options[:db_sign]
      sig = get_from_server options[:user], options[:pass], 'server'
      File.open(Config.instance.file('DB_SIGN'), 'wb') {|f| f.write sig}
      sig = get_from_server options[:user], options[:pass], 'network'
      File.open(Config.instance.file('rcs-network.sig'), 'wb') {|f| f.write sig}
    end

    if options[:db_cert]
      sig = get_from_server options[:user], options[:pass], 'server.pem'
      File.open(Config.instance.file('DB_CERT'), 'wb') {|f| f.write sig} unless sig.nil?
      sig = get_from_server options[:user], options[:pass], 'network.pem'
      File.open(Config.instance.file('rcs-network.pem'), 'wb') {|f| f.write sig} unless sig.nil?
    end

    trace :info, ""
    trace :info, "Current configuration:"
    pp @global

    # save the configuration
    safe_to_file

    return 0
  end

  def get_from_server(user, pass, resource)
    trace :info, "Retrieving #{resource} from the server..."
    begin
      http = Net::HTTP.new(@global['DB_ADDRESS'], @global['DB_PORT'])
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE

      # login
      account = {:user => user, :pass => pass }
      resp = http.request_post('/auth/login', account.to_json, nil)
      if resp['Set-Cookie'].nil?
        puts "Invalid authentication"
        return nil
      else
        cookie = resp['Set-Cookie']
      end
      
      # get the signature or the cert
      res = http.request_get("/signature/#{resource}", {'Cookie' => cookie})
      sig = JSON.parse(res.body)

      # logout
      http.request_post('/auth/logout', nil, {'Cookie' => cookie})
      return sig['value']
    rescue Exception => e
      trace :fatal, "ERROR: auto-retrieve of component failed: #{e.message}"
    end
    trace :info, "done."
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

      opts.separator ""
      opts.separator "Database host:"
      opts.on( '-d', '--db-address HOSTNAME', 'Use the rcs-db at HOSTNAME' ) do |host|
        options[:db_address] = host
      end
      opts.on( '-P', '--db-port PORT', Integer, 'Connect to tcp/PORT on rcs-db' ) do |port|
        options[:db_port] = port
      end

      opts.separator ""
      opts.separator "Collector options:"
      opts.on( '-l', '--listen PORT', Integer, 'Listen on tcp/PORT' ) do |port|
        options[:port] = port
      end
      opts.on( '-b', '--db-heartbeat SEC', Integer, 'Time in seconds between two heartbeats to the rcs-db' ) do |sec|
        options[:hb_interval] = sec
      end
      opts.on( '-H', '--nc-heartbeat SEC', Integer, 'Time in seconds between two heartbeats to the network components' ) do |sec|
        options[:nc_interval] = sec
      end

      opts.separator ""
      opts.separator "General options:"
      opts.on( '-X', '--defaults', 'Write a new config file with default values' ) do
        options[:defaults] = true
      end
      opts.on( '-h', '--help', 'Display this screen' ) do
        puts opts
        return 0
      end

      opts.separator ""
      opts.separator "Utilities:"
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