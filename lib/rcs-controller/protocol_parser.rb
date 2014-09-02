require 'base64'

require 'rcs-common/trace'
require 'rcs-common/crypt'

require_relative 'legacy_network_controller'

module RCS
  module Controller

    STATUS_OK = 200
    STATUS_SERVER_ERROR = 500

    class ProtocolParser
      include RCS::Tracer
      include RCS::Crypt

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

        # TODO: remove legacy code

        if command.has_key? 'command'
          trace :debug, "Received command: #{command.inspect}"
          return protocol_send_command(command)
        else
          trace :debug, "Received LEGACY element: #{command.inspect}"
          return LegacyNetworkController.push(command)
        end

        return STATUS_SERVER_ERROR, "Bad push parsing"
      rescue Exception => e
        trace :error, "Cannot push to anonymizer: #{e.message}"
        trace :debug, e.backtrace.join("\n")
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
        anon_from_cookie(cookie)

        trace :debug, "Anonymizer '#{@anon['name']}' is sending a command..."

        # decrypt the blob
        blob = Base64.decode64(blob)
        command = aes_decrypt(blob, @anon['key'])
        command = JSON.parse(command)

        # TODO: anti replay attack

        return command
      end

      def protocol_encrypt(cookie, command)
        # check that the cookie is valid and belongs to an anon
        anon_from_cookie(cookie)

        trace :debug, "Sending command to anonymizer '#{@anon['name']}'..."

        command = command.to_json

        # encrypt the message
        blob = aes_encrypt(command, @anon['key'])
        blob = Base64.strict_encode64(blob)

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
        trace :error, e.backtrace.join("\n")
        return STATUS_SERVER_ERROR, [{command: 'STATUS', result: {status: 'ERROR', msg: e.message}}]
      end

      def protocol_status(command, response)
        params = command['params']
        status = params['status']
        stats = params['stats']
        msg = params['msg']
        version = params['version']

        # symbolize keys
        stats = stats.inject({}){|h,(k,v)| h.merge({ k.to_sym => v}) }

        name = 'RCS::ANON::' + @anon['name']
        address = @anon['address']

        trace :info, "[NC] [#{name}] #{address} #{status} #{msg}"
        DB.instance.update_status name, address, status, msg, stats, 'anonymizer', version
        DB.instance.update_collector_version(@anon['_id'], version)

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
        @me = anonymizers.select {|x| x['instance'].eql? DB.instance.local_instance}.first
        # and put it in front of the chain
        chain << @me

        # fill the chain with the others
        next_anon = @me['next'].first
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

        # prepare the command for the receiver
        case command['command']
          when 'config'
            msg = {command: 'CONFIG', params: {}, body: command['body']}
            trace :info, "Preparing CONFIG for '#{receiver['name']}' -- #{msg[:body].inspect}"
          when 'upgrade'
            msg = {command: 'UPGRADE', params: {}, body: command['body']}
            trace :info, "Preparing UPGRADE for '#{receiver['name']}' -- #{msg[:body].size} bytes"
          when 'check'
            msg = {command: 'CHECK', params: {}}
            trace :info, "Preparing CHECK for '#{receiver['name']}'"
        end

        # encrypt for the receiver
        msg = protocol_encrypt(receiver['cookie'], msg)

        # calculate the chain to reach the receiver
        chain = forwarding_chain(receiver)

        # encapsulate into FORWARD commands until the first anon (or collector)
        begin
          # check if the only one in the chain is a collector, then send
          break if chain.size.eql? 1

          # encapsulate for the last anon
          forward = {command: 'FORWARD', params: {address: "#{receiver['address']}:#{receiver['port']}", cookie: 'ID=' + receiver['cookie']}, body: msg}
          #trace :debug, "Forward command: " + forward.inspect

          # get the current receiver
          receiver = chain.pop

          # and encrypt for it
          msg = protocol_encrypt(receiver['cookie'], forward)

          trace :debug, "Forwarding through: #{receiver['name']}"

        end until chain.empty?

        trace :info, "Sending complete command to: #{receiver['name']} (#{msg.size} bytes)"
        trace :debug, "Sending complete command to: #{receiver['address']}:#{receiver['port']}"

        resp = nil

        # send the command
        begin
          Timeout::timeout(300) do
            http = Net::HTTP.new(receiver['address'], receiver['port'])
            http.read_timeout = 300
            #http.set_debug_output($stdout)
            resp = http.send_request('POST', '/', msg, {'Cookie' => 'ID=' + receiver['cookie']})
          end
        rescue Exception => ex
          trace :error, "Cannot communicate with #{receiver['name']}: #{ex.message}"
          return STATUS_SERVER_ERROR, "Cannot communicate with #{receiver['name']}: #{ex.message}"
        end

        cookie = resp['Set-Cookie']
        raise("Invalid cookie from anonimizer '#{receiver['name']}'") unless cookie

        # receive, check and decrypt a command
        reply = protocol_decrypt(cookie, resp.body)

        trace :info, "Received response from '#{@anon['name']}': #{reply.inspect}"

        # special case for 'CHECK' request
        if reply['command'].eql? 'STATUS'
          protocol_execute_commands(reply)
          #generate a fake result from the status command
          reply['result'] = {'status' => reply['params']['status']}
        end

        result = reply['result']
        status = result['status']

        return STATUS_OK, status
      end

      def forwarding_chain(anon)
        # we need to have the chain of anon to traverse before sending to the recipient
        # if the anon is in the chain, use it until its position
        # otherwise use the full chain
        # #take_while will take care of all, if not found the chain is the full one
        return @chain.take_while {|x| not x['_id'].eql? anon['_id']}
      end

      def anon_from_cookie(cookie)
        @anon = @anonymizers.select { |x| x['cookie'].eql? cookie.split('=').last }.first
        raise "Invalid cookie" unless @anon
      end

    end

  end
end
