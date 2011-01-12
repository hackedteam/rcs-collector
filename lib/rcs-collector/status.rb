#
#  Status of the process and system
#

# from RCS::Common
require 'rcs-common/trace'

# system

module RCS
module Collector

class Status
  extend RCS::Tracer

  OK = "OK"
  WARN = "WARN"
  ERROR = "ERROR"
  
  def self.my_status
    return @@status || "N/A"
  end

  def self.my_status=(status)
    @@status = status
  end

  def self.disk_free
    #TODO: implement disk free
    return 0
  end

  def self.cpu_load
    #TODO: implement cpu percentage
    return 0
  end

  def self.my_cpu_load
    #TODO: implement process cpu percentage
    return 0
  end

end #Status

end #Collector::
end #RCS::