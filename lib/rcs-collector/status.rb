#
#  Status of the process and system
#

# from RCS::Common
require 'rcs-common/trace'

# system
require 'sys/filesystem'
require 'sys/cpu'

include Sys

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

  # returns the percentage of free space
  def self.disk_free
    # check the filesystem containing the current dir
    stat = Filesystem.stat(Dir.pwd)
    # get the free and total blocks
    free = stat.blocks_free.to_f
    total = stat.blocks.to_f
    # return the percentage (pessimistic)
    return (free / total * 100).floor
  end

  # returns an indicator of the CPU usage in the last minute
  # not exactly the CPU usage percentage, but very close to it
  def self.cpu_load
    # cpu load in the last minute
    load_last_minute = CPU.load_avg.first
    # on multi core systems we have to divide by the number of CPUs
    return (load_last_minute / CPU.num_cpu * 100).floor
  end

  # returns the CPU usage of the current process
  def self.my_cpu_load
    # the first call to it
    @@prev_cpu ||= Process.times
    @@prev_time ||= Time.now

    # calculate the current cpu time
    current_cpu = Process.times

    # diff them and divide by the call interval
    cpu_time = (current_cpu.utime + current_cpu.stime) - (@@prev_cpu.utime + @@prev_cpu.stime)
    cpu_percent = cpu_time / (Time.now - @@prev_time)

    # remember it for the next iteration
    @@previous_times = Process.times
    @@prev_time = Time.now

    return cpu_percent.ceil
  end

end #Status

end #Collector::
end #RCS::
