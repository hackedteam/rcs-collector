require 'eventmachine'
require 'em-http-server'

require 'rcs-common/trace'

require_relative 'protocol_parser'

module RCS
  module Controller

    # This server listen for connections on #LISTENING_PORT.
    # It expects a json string that represents a #Collection object
    # and then delegates it to LegacyNetworkController#push.
    class NetworkController < EM::HttpServer::Server
      include RCS::Tracer
      extend RCS::Tracer

      # Accept only connection from localhost (from the rcs-collector)
      LISTENING_ADDR = "127.0.0.1"

      def process_http_request

        operation = proc do
          begin
            # perform the protocol (all the interesting stuff happens here)
            status, content = ProtocolParser.new(@http_request_method, @http_request_uri, @http_content, @http).act!

          rescue Exception => ex
            trace :error, "Cannot process request: #{ex.message}"
            trace :debug, ex.backtrace.join("\n")

            status = 500
            content = ex.message
          end

          response = EM::DelegatedHttpResponse.new(self)
          response.status = status
          response.content = content
          response
        end

        response = proc do |reply|
          # safe escape on invalid reply
          next unless reply

          # send the actual response
          reply.send_response
        end

        # Let the thread pool handle request
        EM.defer(operation, response)
      end

      def http_request_errback(ex)
        trace(:error, "[errback] #{ex.message} #{ex.backtrace}")
      end

      def self.start
        @server_signature ||= begin
          listening_port = Config.instance.global['CONTROLLER_PORT']
          trace :info, "Starting controller http server #{LISTENING_ADDR}:#{listening_port}..."
          EM::start_server(LISTENING_ADDR, listening_port, self)
        end
      rescue Exception => ex
        raise "Unable to start NetworkController server on port #{listening_port}: #{ex.message}"
      end
    end
  end
end
