require 'eventmachine'
require 'em-http-server'

require 'rcs-common/trace'

module RCS
  module Controller

    # This server listen for connections on #LISTENING_PORT.
    # It expects a json string that represents a #Collection object
    # and then delegates it to Network#push.
    class CheckAnonymizerServer < EM::HttpServer::Server
      include RCS::Tracer
      extend RCS::Tracer

      # Accept only connection from localhost (from the rcs-collector)
      LISTENING_ADDR = "127.0.0.1"

      def process_http_request
        begin
          anon = JSON.parse(@http_content)

          result = Network.push(anon)

          status = 200
          content = 'OK'
        rescue Exception => ex
          trace(:error, "#{ex.message} #{ex.backtrace}")

          status = 500
          content = ex.message
        end

        response = EM::DelegatedHttpResponse.new(self)
        response.status = status
        response.content = content
        response.send_response
      end

      def http_request_errback(ex)
        trace(:error, "[errback] #{ex.message} #{ex.backtrace}")
      end

      def self.start
        @server_signature ||= begin
          listening_port = Config.instance.global['CONTROLLER_PORT']
          trace(:info, "Starting controller http server #{LISTENING_ADDR}:#{listening_port}...")
          EM::start_server(LISTENING_ADDR, listening_port, self)
        end
      rescue Exception => ex
        raise("Unable to start CheckAnonymizer server on port #{listening_port}: #{ex.message}")
      end
    end
  end
end
