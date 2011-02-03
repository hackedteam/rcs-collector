#
#  Network Controller to update the status of the components in the RCS network
#

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

  def self.check
    # we are called from EventMachine, create a thread and return as soon as possible
    Thread.new do


      # retrieve the lists from the db
      elements = DB.instance.proxies
      elements += DB.instance.anonymizers

      threads = []

      # keep only the remote anonymizers discarding the local collectors
      elements.delete_if {|x| x['type'] == 'LOCAL'}

      # keep only the elements to be polled
      #elements.delete_if {|x| x['poll'] == 0}

      if not elements.empty? then
        trace :info, "[NC] Checking #{elements.length} network elements..."
        # send the status to the db
        send_status "Checking #{elements.length} network elements..."
      else
        # send the status to the db
        send_status "Idle..."
      end

      # contact every element
      elements.each do |p|
        threads << Thread.new {
          begin
            Timeout::timeout(Config.instance.global['NC_INTERVAL'].to_i / 2) do
              check_element p
            end
          rescue Exception => e
            trace :warn, "[NC] #{p['address']} #{e.message}"
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

      # ensure to exit
      Thread.exit
    end
  end


  def self.check_element(element)
    #TODO: implement the real check
    puts element.inspect

    socket = TCPSocket.new(element['address'], element['port'])

    ssl_context = OpenSSL::SSL::SSLContext.new()
    ssl_context.cert = OpenSSL::X509::Certificate.new(File.read(Dir.pwd + "/config/" + Config.instance.global['DB_CERT']))
    #ssl_context.key = OpenSSL::PKey::RSA.new(File.open("keys/MyCompanyClient.key"))
    ssl_socket = OpenSSL::SSL::SSLSocket.new(socket, ssl_context)
    ssl_socket.sync_close = true
    ssl_socket.connect

    ssl_socket.puts("GET / HTTP/1.0")
    #ssl_socket.puts("")

    ssl_socket.close
  end


  def self.push(host, content)
    #TODO: implement the real push
    #trace :debug, "network: #{Time.now} -> #{host}"

    return "PUSHED", "text/html"
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
    DB.instance.update_status component, ip, status, message, stats
  end

end

end #Collector::
end #RCS::