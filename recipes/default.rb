#
# Cookbook Name:: bigbluebutton
# Recipe:: default
# Author:: Felipe Cecagno (<felipe@mconf.org>)
# Author:: Mauricio Cruz (<brcruz@gmail.com>)
#
# This file is part of the Mconf project.
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

ruby_block "check system architecture" do
  block do
    raise "This recipe requires a 64 bits machine"
  end
  only_if { node[:kernel][:machine] != "x86_64" }
end

execute "fix dpkg" do
  command "dpkg --configure -a"
  action :run
end

execute "apt-get update"

include_recipe "libvpx" if node['ffmpeg']['install_method'] == :package
include_recipe "ffmpeg"

# add ubuntu repo
apt_repository "ubuntu" do
  uri "http://archive.ubuntu.com/ubuntu/"
  components ["trusty" , "multiverse"]
end

package "software-properties-common"

# add libreoffice repo
apt_repository "libreoffice" do
  uri "ppa:libreoffice/libreoffice-4-3"
  distribution node['lsb']['codename']
end

include_recipe "bigbluebutton::load-properties"

package "wget"

# add bigbluebutton repo
apt_repository node[:bbb][:bigbluebutton][:package_name] do
  key node[:bbb][:bigbluebutton][:key_url]
  uri node[:bbb][:bigbluebutton][:repo_url]
  components node[:bbb][:bigbluebutton][:components]
  notifies :run, 'execute[apt-get update]', :immediately
end

# package response_file isn't working properly, that's why we have to accept the licenses with debconf-set-selections
execute "accept mscorefonts license" do
  user "root"
  command "echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections"
  action :run
end

# install bigbluebutton package
package node[:bbb][:bigbluebutton][:package_name] do
  response_file "bigbluebutton.seed"
  # it will force the maintainer's version of the configuration files
  options "-o Dpkg::Options::='--force-confnew'"
  action :upgrade
  notifies :run, "execute[restart bigbluebutton]", :delayed
end

ruby_block "upgrade dependencies recursively" do
  block do
    bbb_repo = node[:bbb][:bigbluebutton][:repo_url]
    bbb_packages = get_installed_bigbluebutton_packages(bbb_repo)
    all_packages = get_installed_packages()
    upgrade_list = []
    bbb_packages.each do |pkg, version|
      if all_packages.include? pkg
        upgrade_list << "#{pkg}=#{version}"
      end
    end

    command = "apt-get --dry-run --show-upgraded install #{upgrade_list.join(' ')}"
    to_upgrade = `#{command}`.split("\n").select { |l| l.start_with? "Inst" }.collect { |l| l.split()[1] }
    restart_required = ! to_upgrade.empty?

    command = "DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::='--force-confnew' -y --force-yes install #{upgrade_list.join(' ')}"
    Chef::Log.info "Running: #{command}"
    system(command)
    status = $?
    if not status.success?
      raise "Couldn't upgrade the dependencies recursively"
    end

    resources(:ruby_block => "define bigbluebutton properties").run_action(:run)
    if restart_required
      self.notifies :run, "execute[restart bigbluebutton]"
      self.resolve_notification_references
    end
  end
  action :run
end

template "/etc/cron.daily/bigbluebutton" do
  source "bigbluebutton.erb"
  variables(
    :keep_files_newer_than => node[:bbb][:keep_files_newer_than]
  )
end

{ "external.xml" => "/opt/freeswitch/conf/sip_profiles/external.xml" }.each do |k,v|
  cookbook_file v do
    source k
    group "daemon"
    owner "freeswitch"
    mode "0640"
    notifies :run, "execute[restart bigbluebutton]", :delayed
  end
end

template "/opt/freeswitch/conf/vars.xml" do
  source "vars.xml.erb"
  group "daemon"
  owner "freeswitch"
  mode "0640"
  variables(
    lazy {{ :external_ip => node[:bbb][:external_ip] == node[:bbb][:internal_ip]? "auto-nat": node[:bbb][:external_ip] }}
  )
  notifies :run, "execute[restart bigbluebutton]", :delayed
end

package "bbb-demo" do
  if node[:bbb][:demo][:enabled]
    action :upgrade
    notifies :run, "bash[wait for bbb-demo]", :immediately
  else
    action :purge
  end
end

bash "wait for bbb-demo" do
  code <<-EOH
    SECS=10
    while [[ 0 -ne $SECS ]]; do
      if [ -d /var/lib/tomcat7/webapps/demo ] && [ /var/lib/tomcat7/webapps/demo -nt /var/lib/tomcat7/webapps/demo.war ]; then
        echo "bbb-demo deployed!"
        break;
      fi
      sleep 1
      SECS=$[$SECS-1]
    done
  EOH
  action :nothing
end

{ "bbb-check" => node[:bbb][:check][:enabled],
  "bbb-webhooks" => node[:bbb][:webhooks][:enabled],
  "bbb-html5" => node[:bbb][:html5][:enabled] }.each do |pkg, enabled|
  package pkg do
    if enabled
      action :upgrade
    else
      action :purge
    end
    # apt repo could not be building bbb-webhooks yet
    ignore_failure true if pkg == "bbb-webhooks"
  end
end

include_recipe "bigbluebutton::open4"

ruby_block "configure recording workflow" do
    block do
        Dir.glob("/usr/local/bigbluebutton/core/scripts/process/*.rb*").each do |filename|
          format = File.basename(filename).split(".")[0]
          if node[:bbb][:recording][:playback_formats].split(",").include? format
            Chef::Log.info("Enabling record and playback format #{format}");
            command_execute("bbb-record --enable #{format}")
          else
            Chef::Log.info("Disabling record and playback format #{format}");
            command_execute("bbb-record --disable #{format}")
          end
        end
    end
end

execute "check voice application register" do
  command "echo 'Restarting because the voice application failed to register with the sip server'"
  only_if do `bbb-conf --check | grep 'Error: The voice application failed to register with the sip server.' | wc -l`.strip! != "0" end
  notifies :run, "execute[restart bigbluebutton]", :delayed
end

execute "restart bigbluebutton" do
  user "root"
  command "echo 'Restarting'"
  action :nothing
  notifies :run, "execute[set bigbluebutton ip]", :delayed
  notifies :run, "execute[enable webrtc]", :delayed
  notifies :run, "execute[clean bigbluebutton]", :delayed
end

execute "set bigbluebutton salt" do
  user "root"
  command "bbb-conf --setsalt #{node[:bbb][:salt]}"
  action :nothing
  notifies :run, "execute[restart bigbluebutton]", :delayed
end

execute "set bigbluebutton ip" do
  user "root"
  command lazy { "bbb-conf --setip #{node[:bbb][:server_domain]}" }
  action :nothing
  notifies :run, "execute[restart bigbluebutton]", :delayed
end

execute "enable webrtc" do
  user "root"
  command "bbb-conf --enablewebrtc"
  action :nothing
  notifies :create, "template[sip.nginx]", :immediately
end

execute "clean bigbluebutton" do
  user "root"
  command "bbb-conf --clean"
  action :nothing
end

node[:bbb][:recording][:rebuild].each do |record_id|
  execute "rebuild recording" do
    user "root"
    command "bbb-record --rebuild #{record_id}"
    action :run
  end
end
node.set[:bbb][:recording][:rebuild] = []

service "nginx"

template "sip.nginx" do
  path "/etc/bigbluebutton/nginx/sip.nginx"
  source "sip.nginx.erb"
  mode "0644"
  variables(
    lazy {{ :external_ip => node[:bbb][:external_ip] }}
  )
  notifies :reload, "service[nginx]", :immediately
end

ruby_block "reset flag restart" do
  block do
    node.set[:bbb][:force_restart] = false
  end
  only_if do node[:bbb][:force_restart] end
  notifies :run, "execute[restart bigbluebutton]", :delayed
end
    

ruby_block "reset flag setsalt" do
  block do
    node.set[:bbb][:enforce_salt] = nil
    node.set[:bbb][:setsalt_needed] = false
  end
  only_if do node[:bbb][:setsalt_needed] end
  notifies :run, "execute[set bigbluebutton salt]", :delayed
end

ruby_block "reset flag setip" do
  block do
    node.set[:bbb][:setip_needed] = false
  end
  only_if do node[:bbb][:setip_needed] end
  notifies :run, "execute[set bigbluebutton ip]", :delayed
end

# in case we have a cookbook_file to be the default presentation
cookbook_file "/var/www/bigbluebutton-default/default.pdf" do
  source node[:bbb][:default_presentation]
  owner "root"
  group "root"
  mode "0644"
  ignore_failure true
end
