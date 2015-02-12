require 'rcs-common/deploy'

desc "Deploy this project"
task :deploy do
  deploy  = RCS::Deploy.new(user: 'Administrator', address: '192.168.100.100')
  $target = deploy.target
  $me     = deploy.me

  if $me.pending_changes?
    exit unless $me.ask('You have pending changes, continue?')
  end

  root_dir = "Collector"
  components = %w[Collector Carrier Controller]
  services_to_restart = []

  paths = %w[export.zip rcs.lic VERSION VERSION_BUILD].map { |p| "#{$me.path}/config/#{p}" }.join(" ")
  changes = $target.transfer(paths, "rcs/#{root_dir}/config/", trap: true)

  changes = $target.mirror("#{$me.path}/bin/", "rcs/#{root_dir}/bin/", changes: true)
  puts "The #{root_dir}/bin/ folder is "+(changes ? "changed" : "up to date")+"."

  components.each do |service|
    name = service.downcase
    changes = $target.mirror("#{$me.path}/lib/rcs-#{name}/", "rcs/#{root_dir}/lib/rcs-#{name}-release/", changes: true)

    if changes
      services_to_restart << "RCS#{service}"
      puts "#{name} is changed. RCS#{service} service will be restarted soon."
      # puts changes
    else
      puts "#{name} is up to date, nothing was changed."
    end
  end

  services_to_restart.each { |name| $target.restart_service(name) }
end
