require 'helper'
require 'rcs-collector/parser.rb'

class TestRcsParser < Test::Unit::TestCase

  # fake class to hold the Mixin
  class Classy
    include RCS::Collector::Parser
    # fake trace method for testing
    def trace(a, b)
    end
  end

  def test_parser_get_file_not_existent
    c = Classy.new
    content, type = c.http_get_file("ciao")

    assert_nil content
  end

  def test_parser_get_file_in_public

    # create the file to be retrieved
    File.open(Dir.pwd + '/public/test.cod', 'w') { |f| f.write('this is a test') }

    c = Classy.new
    content, type = c.http_get_file("/test.cod")

    File.delete(Dir.pwd + '/public/test.cod')
    
    assert_equal 'this is a test', content
    assert_equal 'application/vnd.rim.cod', type
  end

  def test_parser_get_file_not_in_public

    # create the file to be retrieved
    File.open(Dir.pwd + '/escape', 'w') { |f| f.write('this is a test') }

    c = Classy.new
    content, type = c.http_get_file("/../escape")

    File.delete(Dir.pwd + '/escape')

    # this must not be able to retrieve the file since it is out of the public dir
    assert_not_equal 'this is a test', content
    # this should be empty
    assert_nil type
  end

end
