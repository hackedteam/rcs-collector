Dir["./tasks/helpers.rake", "./tasks/*.rake"].each do |path|
  load(path)
end

task :default => :test

desc "Housekeeping for the project"
task :clean do
  execute "Cleaning the log directory" do
    FileUtils.rm_rf("log")
    FileUtils.mkdir_p("log/err")
  end

  execute "Cleaning the DB cache" do
    FileUtils.rm_f('./config/cache.db')
  end
end
