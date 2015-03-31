namespace :encode do

  case RbConfig::CONFIG['host_os']
    when /darwin/
      paths = ['/Applications/Development/RubyEncoder.app/Contents/MacOS', '/Applications/RubyEncoder.app/Contents/MacOS']
      RUBYENCPATH = File.exists?(paths.first) ? paths.first : paths.last
      RUBYENC = "#{RUBYENCPATH}/rgencoder"
    when /mingw/
      RUBYENCPATH = 'C:/Program Files (x86)/RubyEncoder'
      RUBYENC = "\"C:\\Program Files (x86)\\RubyEncoder\\rgencoder.exe\""
  end

  RUBYENC_VERSION = '2.0.0'

  def exec_rubyencoder(cmd)
    if verbose?
      system(cmd) || raise("Econding failed.")
    else
      raise("Econding failed.") if `#{cmd}` !~ /processed, 0 errors/
    end
  end

  task :rgloader do
    execute "Copying rgloader" do
      FileUtils.rm_rf "#{Dir.pwd}/rgloader"

      RGPATH = RUBYENCPATH + '/Loaders'
      Dir.mkdir "#{Dir.pwd}/rgloader"
      files = Dir[RGPATH + '/**/**']
      files.delete_if {|v| v.match(/bsd/i) or v.match(/linux/i)}
      files.keep_if {|v| v.match(/#{RUBYENC_VERSION.gsub('.','')[0..1]}/) or v.match(/loader.rb/) }
      files.each do |f|
        FileUtils.cp(f, Dir.pwd + '/rgloader')
      end
    end
  end

  task :bin do
    execute "Encrypting bin folder" do
      FileUtils.rm_rf("bin-release")
      FileUtils.cp_r("bin", "bin-release")

      Dir["bin-release/*"].each do |path|
        extname = File.extname(path).downcase
        is_ruby_script = (extname == ".rb") || (extname.empty? and File.read(path) =~ /\#\!.+ruby/i)
        next unless is_ruby_script
        exec_rubyencoder("#{RUBYENC} --stop-on-error --encoding UTF-8 -b- --ruby #{RUBYENC_VERSION} #{path}")
      end
    end
  end

  task :lib do
    execute "Encrypting lib folder" do
      Dir["lib/rcs-*"].each do |path|
        component = File.basename(path)
        FileUtils.rm_rf "lib/#{component}-release"
        FileUtils.mkdir_p "lib/#{component}-release"
        Dir.chdir(path)
        exec_rubyencoder("#{RUBYENC} --stop-on-error --encoding UTF-8 -o ../#{component}-release --ruby #{RUBYENC_VERSION} *.rb")
        Dir.chdir "../.."
      end
    end
  end

end

desc "Remove the protected release code"
task :unprotect do
  execute "Deleting the protected release folder" do
    FileUtils.rm_rf('rgloader')
    FileUtils.rm_rf('bin-release')
    Dir["lib/rcs-*-release"].each { |path| FileUtils.rm_rf(path) }
  end
end

desc "Create the encrypted code for release"
task :protect => [:unprotect, :'encode:rgloader', :'encode:bin', :'encode:lib']

