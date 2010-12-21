#
#  Event handlers
#

# from RCS::Common
require 'rcs-common/trace'

# system
require 'eventmachine'
require 'evma_httpserver'
require 'socket'

module RCS
module Collector

class Handler < EM::Connection
  include EM::HttpServer
  include RCS::Tracer

  def process_http_request

    port, ip = Socket.unpack_sockaddr_in(get_peername)
    trace :info, "Connection from #{ip}"

    resp = EM::DelegatedHttpResponse.new( self )

    # Block which fulfills the request
    operation = proc do
      resp.status = 200
      resp.content = "Hello World!"
    end

    # Callback block to execute once the request is fulfilled
    callback = proc do |res|
    	resp.send_response
    end

    # Let the thread pool (20 Ruby threads) handle request
    EM.defer(operation, callback)
  end
end

class Events

  def setup(port = 80)

    EM::run do
      # if we have epoll(), prefer it over select()
      EM.epoll

      # start the HTTP server
      EM::start_server("0.0.0.0", port, Handler)
      puts "Listening on port #{port}..."

      # set up the timers
      timer = EM::PeriodicTimer.new(5) do
        puts "the time is #{Time.now}"
      end
    end

  end

end #Events::
end #Collector::
end #RCS::

