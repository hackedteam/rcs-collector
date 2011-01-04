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
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    #TODO: client certificate
    #http.auth.ssl.cert_key_file = "mycert.pem"

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

end #

end #Collector::
end #RCS::