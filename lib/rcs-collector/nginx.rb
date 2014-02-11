
require 'rcs-common/trace'
require 'net/http'

require_relative 'config'

module RCS
  module Collector
    module Nginx
      extend self
      extend RCS::Tracer

      @allow = "127.0.0.0/8"

      def start
        trace :info, "Staring Nginx on port #{Config.instance.global['LISTENING_PORT']}"
        ret = system "#{nginx_executable} -c #{config_file} -p #{Dir.pwd}"
        ret or raise("Failed to start nginx process")
      end

      def stop(silent = false)
        trace :info, "Stopping Nginx"
        ret = system "#{nginx_executable} -c #{config_file} -p #{Dir.pwd} -s stop"
        return if silent
        ret or raise("Failed to stop nginx process")
      end

      def stop!
        stop(true)
        trace :info, "Hard killing Nginx process (if any)"
        # ensure the process is not running (kill hard)
        system "#{kill_command} #{File.basename(nginx_executable)}"
      end

      def reload
        trace :info, "Reloading Nginx configuration"
        ret = system "#{nginx_executable} -c #{config_file} -p #{Dir.pwd} -s reload"
        ret or raise("Failed to reload nginx configuration")
      end

      def status
        http = Net::HTTP.new('127.0.0.1', 80)
        resp = http.request_get('/nginx_status')
        return :unknown unless resp.kind_of? Net::HTTPSuccess
        return :running if resp.body =~ /Active connections/
      rescue Exception => e
        trace :debug, "Cannot get Nginx status: #{e.message}"
        return :error
      end

      def nginx_executable
        case RbConfig::CONFIG['host_os']
          when /darwin/
            './bin/nginx'
          when /mingw/
            'bin\nginx.exe'
        end
      end

      def kill_command
        case RbConfig::CONFIG['host_os']
          when /darwin/
            'killall -9'
          when /mingw/
            'taskkill /F /IM'
        end
      end

      def save_config
        File.write(config_file, config)
      end

      def first_hop=(anon_address)
        trace :info, "Nginx accepting connection only from #{anon_address}"
        @allow = anon_address
      end

      def config_file
        Config.instance.file("nginx.conf")
      end

      def config
        %"
        #{c_global}
        #{c_events}
        #{c_http}
        "
      end

      def c_global
        %"
        worker_processes  2;
        error_log  log/error.log;
        pid        log/nginx.pid;
        "
      end

      def c_events
        %"
        events {
            worker_connections  1024;
        }
        "
      end

      def c_http
        %"
        http {
            default_type  application/octet-stream;

            log_format  main  '$remote_addr - $remote_user [$time_local] \"$request\" '
                              '$status $body_bytes_sent \"$http_referer\" '
                              '\"$http_user_agent\" \"$http_x_forwarded_for\"';

            access_log  log/access.log  main;

            # List of Allowed HTTP methods
            map $request_method $bad_method {
              default 1;
              ~(?i)(GET|HEAD|POST|PUSH|PUT|DELETE|WATCHDOG|PROXY) 0;
            }

            keepalive_timeout  65;
            gzip  on;
            client_body_temp_path /tmp;

            #{c_server}
        }"
      end

      def c_server
        %"
             server {
                listen        #{Config.instance.global['LISTENING_PORT']};
                server_name   localhost;
                server_tokens off;

                # Deny access based on HTTP method
                if ($bad_method = 1) {
                  return 405;
                }

                # status page
                location /nginx_status {
                  stub_status on;
                  access_log off;
                  allow 127.0.0.1;
                  deny all;
                }

                # Proxy all the request to the collector
                location / {
                  proxy_pass        http://localhost:#{Config.instance.global['LISTENING_PORT'] + 1};
                  proxy_set_header  X-Forwarded-For  $proxy_add_x_forwarded_for;
                  allow #{@allow};
                  deny all;
                }
            }
        "
      end
    end
  end
end

if __FILE__ == $0
  puts RCS::Collector::Nginx.status
  RCS::Collector::Nginx.stop!
  #puts RCS::Collector::Nginx.config
  RCS::Collector::Nginx.first_hop = "1.2.3.4/32"
  RCS::Collector::Nginx.save_config
  RCS::Collector::Nginx.start
  gets
  RCS::Collector::Nginx.first_hop = "0.0.0.0/0"
  RCS::Collector::Nginx.save_config
  RCS::Collector::Nginx.reload
  puts RCS::Collector::Nginx.status
  gets
  RCS::Collector::Nginx.stop
end