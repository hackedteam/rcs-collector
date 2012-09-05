require 'helper'

# fake class to hold the Mixin
class Classy < RCS::Collector::CollectorController

  def initialize
    @request = {peer: "test_peer", headers: {host: "testhost"}}
  end

  # fake trace method for testing
  def trace(a, b)
  end
end

class TestParser < Test::Unit::TestCase

  def setup
    # ensure the directory is present
    Dir::mkdir(Dir.pwd + RCS::Collector::PUBLIC_DIR) if not File.directory?(Dir.pwd + RCS::Collector::PUBLIC_DIR)
    @headers = {:user_agent => "Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_6_6; en-US)"}
  end

  def test_parser_get_file_not_existent
    c = Classy.new
    content = c.http_get_file(@headers, "/ciao")

    assert_equal 404, content.status
  end

  def test_parser_get_file_in_public
    # create the file to be retrieved
    File.open(Dir.pwd + RCS::Collector::PUBLIC_DIR + '/test.cod', 'w') { |f| f.write('this is a test') }

    c = Classy.new
    content = c.http_get_file(@headers, "/test.cod")

    File.delete(Dir.pwd + RCS::Collector::PUBLIC_DIR + '/test.cod')
    
    assert_equal RCS::Collector::RESTFileStream, content.class
  end

  def test_parser_get_file_not_in_public
    # create the file to be retrieved
    File.open(Dir.pwd + '/escape', 'w') { |f| f.write('this is a test') }

    c = Classy.new
    content = c.http_get_file(@headers, "/../escape")

    File.delete(Dir.pwd + '/escape')

    # this must not be able to retrieve the file since it is out of the public dir
    assert_not_equal RCS::Collector::RESTFileStream, content.class
    assert_equal 404, content.status
  end

  def test_parser_get_file_with_specific_platform
    # create the file for macos
    File.open(Dir.pwd + RCS::Collector::PUBLIC_DIR + '/test.app', 'w') { |f| f.write('this is a test app') }

    c = Classy.new
    # ask for 'test', we should receive the test.app file
    content, type = c.http_get_file(@headers, "/test")

    File.delete(Dir.pwd + RCS::Collector::PUBLIC_DIR + '/test.app')

    assert_equal 'this is a test app', content
    assert_equal 'binary/octet-stream', type
  end

  def test_parser_put_file
    c = Classy.new
    test_file = '/test-put-file'
    test_content = 'this is a test'

    # this should create the file
    ret, type = c.http_put_file(test_file, test_content)

    assert_equal 'OK', ret
    assert_equal 'text/html', type
    assert_true File.exist?(Dir.pwd + RCS::Collector::PUBLIC_DIR + test_file)
    assert_equal test_content, File.read(Dir.pwd + RCS::Collector::PUBLIC_DIR + test_file)
    
    # cleanup the test file
    File.delete(Dir.pwd + RCS::Collector::PUBLIC_DIR + test_file)
  end

  def test_parser_put_file_with_subdir
    c = Classy.new
    test_dir = '/test-dir'
    test_file = '/test-put-file'
    test_content = 'this is a test'

    # this should create the file
    ret, type = c.http_put_file(test_dir + test_file, test_content)

    assert_equal 'OK', ret
    assert_equal 'text/html', type
    assert_true File.exist?(Dir.pwd + RCS::Collector::PUBLIC_DIR + test_dir + test_file)
    assert_equal test_content, File.read(Dir.pwd + RCS::Collector::PUBLIC_DIR + test_dir + test_file)

    # cleanup the test file
    File.delete(Dir.pwd + RCS::Collector::PUBLIC_DIR + test_dir + test_file)
    Dir.delete(Dir.pwd + RCS::Collector::PUBLIC_DIR + test_dir)
  end

end
