#
# Module to get the external ip address
#

require 'open-uri'

module RCS
module Collector

class MyIp
  extend RCS::Tracer

  def self.get
    # don't perform resolution if not wanted
    return '' unless Config.instance.global['RESOLVE_IP']

    address = ''
    
    Timeout::timeout(2) do
      # http://automation.whatismyip.com/n09230945.asp  (does not work anymore)
      # curl ifconfig.me
      # curl icanhazip.com
      address = open("http://bot.whatismyipaddress.com") {|f| f.read}
    end

    # check if it's a valid ip address
    return '' if /^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$/.match(address).nil?

    trace :info, "External ip address is: #{address}"
    return address

  rescue Exception => e
    trace :warn, "Cannot get external ip address: #{e.message}"
    return ''
  end

end

end # Collector::
end # RCS::