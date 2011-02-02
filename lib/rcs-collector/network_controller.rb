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

    #TODO: implement the real check

    trace :debug, "network: #{Time.now}"
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