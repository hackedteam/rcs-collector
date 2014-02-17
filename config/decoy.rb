require 'securerandom'
require 'rcs-common/trace'

class FakeServer
  SERVER_STRING = "nginx"
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
  HTTP_STATUS_BAD_GATEWAY = 502

  def self.create(request)

    ###############################################################
    # you can inspect the request headers to reply with different
    # pages based on the requester address or destination hostname
    # uncomment the line below to check how the hash is made up
    ###############################################################
    #trace :info, "Request parameters: " + request.inspect

    # Only for old anonymizers DO NOT EDIT!!
    old = "<!DOCTYPE HTML PUBLIC \"-//IETF//DTD HTML 2.0//EN\">\n" +
          "<html><head>\n" +
          "<title>404 Not Found</title>\n" +
          "</head><body>\n" +
          "<h1>Not Found</h1>\n" +
          "<p>The requested URL #{request[:uri]} was not found on this server.</p>\n" +
          "<hr>\n" +
          "<address>Apache/2.4.7 (Unix) OpenSSL/1.0.1e Server at #{request[:headers][:host]} Port 80</address>\n" +
          "</body></html>\n"
    return HTTP_STATUS_NOT_FOUND, old, {content_type: 'text/html'} unless request[:anon_version] >= '2014022401'

    ###############################################
    # Example: standard nginx not found document
    ###############################################
    not_found = "<html>\r\n" +
           "<head><title>404 Not Found</title></head>\r\n" +
           "<body bgcolor=\"white\">\r\n" +
           "<center><h1>404 Not Found</h1></center>\r\n" +
           "<hr><center>nginx</center>\r\n" +
           "</body>\r\n" +
           "</html>\r\n"

    bad_gateway = "<html>\r\n" +
           "<head><title>502 Bad Gateway</title></head>\r\n" +
           "<body bgcolor=\"white\">\r\n" +
           "<center><h1>502 Bad Gateway</h1></center>\r\n" +
           "<hr><center>nginx</center>\r\n" +
           "</body>\r\n" +
           "</html>\r\n"

    return HTTP_STATUS_NOT_FOUND, not_found, {content_type: 'text/html'}
  end

end

class BadRequestPage
  extend RCS::Tracer

  def self.create(request)

    ###############################################
    # Example: standard nginx bad request document
    ###############################################
    page = "<html>\r\n" +
           "<head><title>400 Bad Request</title></head>\r\n" +
           "<body bgcolor=\"white\">\r\n" +
           "<center><h1>400 Bad Request</h1></center>\r\n" +
           "<hr><center>nginx</center>\r\n" +
           "</body>\r\n" +
           "</html>\r\n"

    return page, {content_type: 'text/html'}
  end

end

class NotAllowedPage
  extend RCS::Tracer

  def self.create(request)

    ######################################################
    # Example: standard nginx method not allowed document
    ######################################################
    page = "<html>\r\n" +
           "<head><title>405 Not Allowed</title></head>\r\n" +
           "<body bgcolor=\"white\">\r\n" +
           "<center><h1>405 Not Allowed</h1></center>\r\n" +
           "<hr><center>nginx</center>\r\n" +
           "</body>\r\n" +
           "</html>\r\n"

    return page, {content_type: 'text/html'}
  end

end