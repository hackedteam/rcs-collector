require 'helper'

module RCS
module Collector

class TestRcsCollector < Test::Unit::TestCase

  # dirty hack to fake the trace function
  class RCS::Collector::SessionManager
    def trace(a, b)
    end
  end

  def test_sessions
    cookie = SessionManager.instance.create(1, "BUILD", "INSTANCE", "TYPE", "KEY")

    # just created sessions must be valid
    valid = SessionManager.instance.check(cookie)
    assert_true valid

    # check the values of the session
    session = SessionManager.instance.get(cookie)
    assert_equal "BUILD", session[:build]

    assert_equal 1, SessionManager.instance.length

    # simulate the timeout
    sleep 2

    # force the timeout (in 1 second) of the session
    SessionManager.instance.timeout(1)

    # the session must now be nil since it was timeouted
    session = SessionManager.instance.get(cookie)
    assert_nil session

    assert_equal 0, SessionManager.instance.length

  end
end

end #Collector::
end #RCS::
