source "http://rubygems.org"
# Add dependencies required to use your gem here.

# Specify your gem's dependencies in rcs-collector.gemspec
#gemspec

gem "rcs-common", ">= 9.2.3", :path => "../rcs-common"

gem 'eventmachine', ">= 1.0.3"
gem 'em-http-server', ">= 0.1.7"
gem 'persistent_http'
gem 'uuidtools'
gem 'rubyzip', "= 1.0.0"

#platforms :ruby do
  gem 'sqlite3'
#end

platforms :jruby do
  gem 'json'
  gem 'jruby-openssl'
  gem 'jdbc-sqlite3'
end

# Add dependencies to develop your gem here.
# Include everything needed to run rake, tests, features, etc.
group :development do
  gem "bundler", "> 1.0.0"
  gem 'rake'
  gem 'test-unit'
  gem 'pry'
end
