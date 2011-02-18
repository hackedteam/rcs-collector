require 'helper'

# fake class to hold the Mixin
class Classy
  include RCS::Collector::Parser
  # fake trace method for testing
  def trace(a, b)
  end
end

class TestParser < Test::Unit::TestCase

  def setup
    # ensure the directory is present
    Dir::mkdir(Dir.pwd + '/public') if not File.directory?(Dir.pwd + '/public')
    @headers = ["User-Agent: Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_6_6; en-US)"]
  end

  def test_parser_get_file_not_existent
    c = Classy.new
    content, type = c.http_get_file(@headers, "/ciao")

    assert_nil content
  end

  def test_parser_get_file_in_public
    # create the file to be retrieved
    File.open(Dir.pwd + '/public/test.cod', 'w') { |f| f.write('this is a test') }

    c = Classy.new
    content, type = c.http_get_file(@headers, "/test.cod")

    File.delete(Dir.pwd + '/public/test.cod')
    
    assert_equal 'this is a test', content
    assert_equal 'application/vnd.rim.cod', type
  end

  def test_parser_get_file_not_in_public
    # create the file to be retrieved
    File.open(Dir.pwd + '/escape', 'w') { |f| f.write('this is a test') }

    c = Classy.new
    content, type = c.http_get_file(@headers, "/../escape")

    File.delete(Dir.pwd + '/escape')

    # this must not be able to retrieve the file since it is out of the public dir
    assert_not_equal 'this is a test', content
    # this should be empty
    assert_nil type
  end

  def test_parser_get_file_with_specific_platform
    # create the file for macos
    File.open(Dir.pwd + '/public/test.app', 'w') { |f| f.write('this is a test app') }

    c = Classy.new
    # ask for 'test', we should receive the test.app file
    content, type = c.http_get_file(@headers, "/test")

    File.delete(Dir.pwd + '/public/test.app')

    assert_equal 'this is a test app', content
    assert_equal 'binary/octet-stream', type
  end

end
