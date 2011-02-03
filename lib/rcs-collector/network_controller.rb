#
#  Network Controller to update the status of the components in the RCS network
#

# from RCS::Common
require 'rcs-common/trace'

# system

module RCS
module Collector

class NetworkController
  extend RCS::Tracer

  def self.check
    # send the status to the db
    send_status

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
    end

    # contact every element
    elements.each do |p|
      threads << Thread.new {
        #TODO: implement the real check
        puts p.inspect
      }
    end

    # wait for all the threads to finish
    threads.each do |t|
      t.join
    end

    trace :info, "[NC] Network elements check completed"
  end

  def self.push(host, content)
    #TODO: implement the real push
    #trace :debug, "network: #{Time.now} -> #{host}"

    return "PUSHED", "text/html"
  end

  def self.send_status
    # report our status to the db
    component = "RCS::NetworkController"
    ip = ''

    # always idle
    message = "Idle..."

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