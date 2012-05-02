source "http://rubygems.org"
# Add dependencies required to use your gem here.

# Specify your gem's dependencies in rcs-collector.gemspec
#gemspec

gem "rcs-common", ">= 8.0.0", :path => "../rcs-common"

gem 'eventmachine', ">= 1.0.0.beta.4"
gem 'em-http-server'
platforms :jruby do
  gem 'jdbc-sqlite3'
end
platforms :ruby do
  gem 'sqlite3'
end
gem 'uuidtools'
gem 'rubyzip', ">= 0.9.5"

# Add dependencies to develop your gem here.
# Include everything needed to run rake, tests, features, etc.
group :development do
  gem "bundler", "> 1.0.0"
  gem 'test-unit'
end
