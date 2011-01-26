#
#  Configuration parsing module
#

# from RCS::Common
require 'rcs-common/trace'

# system
require 'singleton'
require 'yaml'

module RCS
module Collector

class Config
  include Singleton
  include Tracer

  CONF_FILE = '/config/config.yaml'

  attr_reader :global

  def initialize
    @global = {}
  end

  def load_from_file
    trace :info, "Loading configuration file..."

    conf_file = Dir.pwd + CONF_FILE

    # load the config in the @global hash
    begin
      File.open(conf_file, "r") do |f|
        @global = YAML.load(f.read)
      end
    rescue
      trace :fatal, "Cannot open config file [#{conf_file}]"
      exit
    end
  end

  def safe_to_file
    #TODO: save the config in the file
  end

  # executed from rcs-collector-config
  def self.run!(*argv)
    #TODO: optionparse program
    puts "CONFIG RUN"
  end

end #Config
end #Collector::
end #RCS::