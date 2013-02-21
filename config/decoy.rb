require 'securerandom'
require 'rcs-common/trace'

class DecoyPage
  extend RCS::Tracer

  HTTP_STATUS_OK = 200
  HTTP_STATUS_REDIRECT = 302
  HTTP_STATUS_BAD_REQUEST = 400
  HTTP_STATUS_NOT_FOUND = 404
  HTTP_STATUS_NOT_AUTHORIZED = 403
  HTTP_STATUS_CONFLICT = 409
  HTTP_STATUS_SERVER_ERROR = 500

  def self.create(request)

    ###############################################################
    # you can inspect the request headers to reply with different
    # pages based on the requester address or destination hostname
    # uncomment the line below to check how the hash is made up
    ###############################################################
    #trace :info, "Request parameters: " + request.inspect

    ####################################
    # Example: google redirection page
    ####################################
    #page = "<html> <head>" +
    #       "<meta http-equiv=\"refresh\" content=\"0;url=http://www.google.com\">" +
    #       "</head> </html>"

    ###############################################
    # Example: standard apache not found document
    ###############################################
    page = "<!DOCTYPE HTML PUBLIC \"-//IETF//DTD HTML 2.0//EN\">" +
          "<html><head>" +
          "<title>404 Not Found</title>" +
          "</head><body>" +
          "<h1>Not Found</h1>" +
          "<p>The requested URL #{request[:uri]} was not found on this server.</p>" +
          "<hr>" +
          "<address>Apache/2.4.3 (Unix) OpenSSL/1.0.0g Server at #{request[:headers][:host]} Port 80</address>" +
          "</body></html>"

    return HTTP_STATUS_NOT_FOUND, page, {content_type: 'text/html'}
  end

end