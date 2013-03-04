require 'securerandom'
require 'rcs-common/trace'

class FakeServer
  SERVER_STRING = "Apache/2.4.4 (Unix) OpenSSL/1.0.0g"
end

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
    page = "<!DOCTYPE HTML PUBLIC \"-//IETF//DTD HTML 2.0//EN\">\n" +
          "<html><head>\n" +
          "<title>404 Not Found</title>\n" +
          "</head><body>\n" +
          "<h1>Not Found</h1>\n" +
          "<p>The requested URL #{request[:uri]} was not found on this server.</p>\n" +
          "<hr>\n" +
          "<address>#{FakeServer::SERVER_STRING} Server at #{request[:headers][:host]} Port 80</address>\n" +
          "</body></html>\n"

    return HTTP_STATUS_NOT_FOUND, page, {content_type: 'text/html'}
  end

end

class BadRequestPage
  extend RCS::Tracer

  def self.create(request)

    ###############################################
    # Example: standard apache bad request document
    ###############################################
    page = "<!DOCTYPE HTML PUBLIC \"-//IETF//DTD HTML 2.0//EN\">\n" +
          "<html><head>\n" +
          "<title>400 Bad Request</title>\n" +
          "</head><body>\n" +
          "<h1>Bad Request</h1>\n" +
          "<p>Your browser sent a request that this server could not understand.<br />\n" +
          "</p>\n" +
          "<hr>\n" +
          "<address>#{FakeServer::SERVER_STRING} Server at #{request[:headers][:host]} Port 80</address>\n" +
          "</body></html>\n"

    return page, {content_type: 'text/html'}
  end

end