#
#  Cache management for the db
#

# from RCS::Common
require 'rcs-common/trace'

# system
require 'sqlite3'

module RCS
module Collector

class Cache
  extend RCS::Tracer

  def self.empty!
    #TODO: implement
  end

  def self.length
    #TODO: implement
    return 1
  end

  def self.signature=(sig)
    #TODO: implement
  end

  def self.signature
    #TODO: implement
    return "ciccio"
  end

  def self.add_class_keys(class_key)
    #TODO: implement
  end

  def self.class_keys
      #TODO: implement
    return {}
  end

end #Cache

end #Collector::
end #RCS::