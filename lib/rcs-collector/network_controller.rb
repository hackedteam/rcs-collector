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

  def self.perform
    #TODO: implement the real check
    trace :debug, "network: #{Time.now}"
  end

  def self.push(host, content)
    #TODO: implement the real push
    #trace :debug, "network: #{Time.now} -> #{host}"

    return "PUSHED", "text/html"
  end
end

end #Collector::
end #RCS::