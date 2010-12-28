#
#  HTTP requests parsing module
#

# relatives
require_relative 'network_controller.rb'

# from RCS::Common
require 'rcs-common/trace'


module RCS
module Collector

module Parser
  include RCS::Tracer

  # parse a request from a client
  #
  def http_parse(req_method, req_uri, req_cookie, req_content)

    # default values
    resp_content = ""
    resp_content_type = "text/html"
    resp_cookie = nil

    case req_method
      when 'GET'
        # serve the requested file
        resp_content, resp_content_type = http_get_file req_uri
        # the file was not found, display the decoy
        resp_content, resp_content_type = http_decoy_page if resp_content.length == 0

      when 'POST'
        #TODO: implement the REST protocol
        trace :debug, req_method

      when 'PUT'
        # only the DB is authorized to send PUSH commands
        if @peer.eql? Config.instance.global['DB_ADDRESS'] then
          # send a PUSH notification to the Network Element
          resp_content, resp_content_type = NetworkController.push req_uri.delete('/'), req_content
        else
          trace :error, "HACK ALERT: #{@peer} is trying to send PUSH commands to NC !!!"
          resp_content, resp_content_type = http_decoy_page
        end

      else
        # everything that we don't understand will get the decoy page
        resp_content, resp_content_type = http_decoy_page
    end

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
  def http_get_file(uri)

    content = ""

    # search the file in the public directory
    file_path = Dir.pwd + '/public' + uri

    trace :info, "[#{@peer}] serving #{file_path}"

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
    if real.start_with? Dir.pwd + '/public' then
      # load the content of the file
      begin
        content = File.read(file_path) if File.exist?(file_path) and File.file?(file_path)
      rescue
        content = ''
      end
    end

    if content.length != 0
      trace :info, "[#{@peer}] " + File.size(file_path).to_s + " bytes served"
    else
      trace :info, "[#{@peer}] file not found"
    end

    return content
  end

end #Parser

end #Collector::
end #RCS::