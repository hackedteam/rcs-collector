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

  attr_reader :global

  def initialize
    @global = {}
  end

  def load_from_file
    trace :info, "Loading configuration file..."

    conf_file = Dir.pwd + '/config/config.yaml'

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
  
end #Config
end #Collector::
end #RCS::