source "http://rubygems.org"
# Add dependencies required to use your gem here.

# Specify your gem's dependencies in rcs-collector.gemspec
#gemspec

gem "rcs-common", ">= 8.0.0", :path => "../rcs-common"

#git "git://github.com/alor/eventmachine.git", :branch => "master" do
  gem 'eventmachine', ">= 1.0.0.beta.4"
#end
git "git://github.com/alor/evma_httpserver.git", :branch => "master" do
  gem 'eventmachine_httpserver', ">= 0.2.2"
end
gem 'sqlite3'
gem 'uuidtools'
gem 'rubyzip', ">= 0.9.5"

# Add dependencies to develop your gem here.
# Include everything needed to run rake, tests, features, etc.
group :development do
  gem "bundler", "> 1.0.0"
  gem 'simplecov'
  gem 'test-unit'
end
