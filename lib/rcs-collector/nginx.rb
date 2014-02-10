#require_relative 'config'

module RCS
  module Collector
    module Nginx
      extend self

      @allow = "127.0.0.0/8"

      def start
        # TODO: execute: nginx.exe -c #{config_file} -p #{Dir.pwd}
      end

      def stop
        # TODO: execute: nginx.exe -c #{config_file} -p #{Dir.pwd} -s stop
      end

      def stop!
        # TODO: execute taskkill /F /IM nginx.exe
      end

      def reload
        # TODO: execute: nginx.exe -c #{config_file} -p #{Dir.pwd} -s reload
      end

      def save_config
        File.write(config_file, config)
      end

      def first_hop=(anon_address)
        @allow = anon_address
      end

      def config_file
        #Config.instance.file("nginx.conf")
        "config/nginx2.conf"
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
                listen        80;
                server_name   localhost;
                server_tokens off;

                # Deny access based on HTTP method
                if ($bad_method = 1) {
                  return 405;
                }

                # Proxy all the request to the collector
                location / {
                  proxy_pass        http://localhost:81;
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
  #RCS::Collector::Nginx.first_hop = "0.0.0.0/0"
  puts RCS::Collector::Nginx.config
  RCS::Collector::Nginx.save_config
end