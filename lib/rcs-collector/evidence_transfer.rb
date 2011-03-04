#
#  Evidence Transfer module for transferring evidence to the db
#

# from RCS::Common
require 'rcs-common/trace'
require 'rcs-common/evidence_manager'

# system
require 'singleton'

module RCS
module Collector

class EvidenceTransfer
  include Singleton
  include RCS::Tracer

  def send_cached
    trace :info, "Transferring cached evidence to the db..."
    
    EvidenceManager.instance.instances.each do |instance|
      trace :debug, instance
    end

  end

  def notify(session)
    trace :debug, "Notify transfer #{session}"
  end

end
  
end #Collector::
end #RCS::