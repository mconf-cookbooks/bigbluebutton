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

require 'nokogiri'

ruby_block "check system architecture" do
  block do
    raise "This recipe requires a 64 bits machine"
  end
  only_if { node['kernel']['machine'] != "x86_64" }
end

include_recipe "bigbluebutton::gem-deps"

execute "apt-get update"

# purge ffmpeg package if we intend to install from source
dpkg_package "ffmpeg" do
  action :remove
  only_if { node['ffmpeg']['install_method'] == :source }
end

include_recipe "libvpx" if node['ffmpeg']['install_method'] == :package
include_recipe "ffmpeg"

# add ubuntu repo
apt_repository "ubuntu" do
  uri "http://archive.ubuntu.com/ubuntu/"
  distribution "trusty"
  components ["multiverse"]
end

package "software-properties-common"

# add libreoffice repo
apt_repository "libreoffice" do
  uri "ppa:libreoffice/libreoffice-4-4"
  distribution node['lsb']['codename']
end

# add php repo for libssl 1.0.2 needed for chrome 52
apt_repository "ondrej-php" do
  uri "ppa:ondrej/php"
  distribution node['lsb']['codename']
end

include_recipe "bigbluebutton::load-properties"

package "wget"

# add bigbluebutton repo
apt_repository node['bbb']['bigbluebutton']['package_name'] do
  key node['bbb']['bigbluebutton']['key_url']
  uri node['bbb']['bigbluebutton']['repo_url']
  distribution node['bbb']['bigbluebutton']['dist']
  components node['bbb']['bigbluebutton']['components']
  notifies :run, 'execute[apt-get update]', :immediately
end

# package response_file isn't working properly, that's why we have to accept the licenses with debconf-set-selections
execute "accept mscorefonts license" do
  user "root"
  command "echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections"
  action :run
end

# install bigbluebutton package
package node['bbb']['bigbluebutton']['package_name'] do
  response_file "bigbluebutton.seed"
  # it will force the maintainer's version of the configuration files
  options "-o Dpkg::Options::='--force-confnew'"
  action :upgrade
  notifies :run, "execute[restart bigbluebutton]", :delayed
end

package "apt-rdepends"

ruby_block "upgrade dependencies recursively" do
  block do
    bbb_repo = node['bbb']['bigbluebutton']['repo_url']
    # load packages installed by the bigbluebutton repository
    bbb_packages = get_installed_bigbluebutton_packages(bbb_repo)
    # load all packages installed
    all_packages = get_installed_packages()
    upgrade_list = []
    # set the versions available on the repository - the exact versions are going to be installed
    bbb_packages.each do |pkg, version|
      if all_packages.include? pkg
        upgrade_list << "#{pkg}=#{version}"
      end
    end

    # dependencies aren't upgraded by default, so we need a specific procedure for that
    reset_auto = []
    if node['bbb']['bigbluebutton']['upgrade_dependencies']
      bbb_package_name = node['bbb']['bigbluebutton']['package_name']
      # load all dependencies of the bigbluebutton package
      bbb_deps = get_bigbluebutton_dependencies(bbb_package_name)
      
      # load the upgrades available, and insert to the upgrade_list the dependencies that we need to update
      command = "apt-get --dry-run --show-upgraded upgrade"
      to_upgrade = `#{command}`.split("\n").select { |l| l.start_with? "Conf" }.collect { |l| l.split()[1] }
      upgrade_list += (bbb_deps.keys - bbb_packages.keys) & to_upgrade

      # get the list of packages marked as automatically installed, so we can upgrade and reset the mark later
      reset_auto = bbb_deps.select { |key, value| value == :auto }.keys & to_upgrade
    end

    # check if any package will be upgraded, so we need to restart the service
    command = "apt-get --dry-run --show-upgraded install #{upgrade_list.join(' ')}"
    to_upgrade = `#{command}`.split("\n").select { |l| l.start_with? "Inst" }.collect { |l| l.split()[1] }
    restart_required = ! to_upgrade.empty?

    # run the upgrade
    command = "DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::='--force-confnew' -y --force-yes install #{upgrade_list.join(' ')}"
    Chef::Log.info "Running: #{command}"
    system(command)
    upgrade_status = $?

    if ! reset_auto.empty?
      # reset the automatically installed mark in the packages
      command = "apt-mark auto #{reset_auto.join(' ')}"
      Chef::Log.info "Running: #{command}"
      system(command)
      status = $?
      Chef::Log.error "Couldn't reset properly the list of automatically installed packages" if ! status.success?
    end

    # even if the upgrade fails, we reset the automatically installed mark BEFORE raising an exception
    raise "Couldn't upgrade the dependencies recursively" if ! upgrade_status.success?

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
    :keep_files_newer_than => node['bbb']['keep_files_newer_than'],
    :logs_max_history => node['bbb']['logs_max_history']
  )
end

template "/etc/cron.daily/remove-recordings-raw" do 
  source "remove-recordings-raw.erb"
  variables(
    :recording_raw_max_retention => node['bbb']['recording_raw_retention']['max_retention']
  )
  mode "0755"
  if node['bbb']['recording_raw_retention']['remove_old_recordings']
    action :create
  else
    action :delete
  end
end

# handle the imagemagick vulnerability detailed here: https://groups.google.com/forum/#!topic/bigbluebutton-setup/s5zeNpg5M8I
ruby_block "fix imagemagick vulnerability" do
  block do
    xml_filename = "/etc/ImageMagick/policy.xml"
    if File.exists? xml_filename
        doc = Nokogiri::XML(File.open(xml_filename)) { |x| x.noblanks }
        modified = false
        [ "EPHEMERAL", "URL", "HTTPS", "MVG", "MSL" ].each do |pattern|
            node = doc.at_xpath("/policymap/policy[@domain='coder' and @rights='none' and @pattern='#{pattern}']")
            if node.nil?
                puts "Adding attribute for #{pattern}"
                node = Nokogiri::XML::Node.new "policy", doc
                node["domain"] = "coder"
                node["rights"] = "none"
                node["pattern"] = pattern
                doc.at("/policymap") << node
                modified = true
            end
        end
        
        if modified
          xml_file = File.new(xml_filename, "w")
          xml_file.write(doc.to_xml(:indent => 2))
          xml_file.close
        end
    end
  end
end

logrotate_app 'remove-recordings-raw' do
  cookbook 'logrotate'
  path '/var/log/bigbluebutton/remove-recordings-raw.log'
  options ['missingok', 'compress', 'copytruncate', 'notifempty', 'dateext']
  frequency node['bbb']['recording_raw_retention']['logrotate']['frequency']
  rotate node['bbb']['recording_raw_retention']['logrotate']['rotate']
  size node['bbb']['recording_raw_retention']['logrotate']['size']
  dateformat node['bbb']['recording_raw_retention']['logrotate']['frequency'] == 'monthly' ? '%Y%m' : '%Y%m%d'
  template_mode "0644"
  create "644 root root"
end

logrotate_app 'tomcat7' do
  cookbook 'logrotate'
  path '/var/log/tomcat7/catalina.out'
  options ['missingok', 'compress', 'copytruncate', 'notifempty', 'dateext']
  frequency node['bbb']['logrotate']['frequency']
  rotate node['bbb']['logrotate']['rotate']
  size node['bbb']['logrotate']['size']
  template_mode "0644"
  create "644 tomcat7 root"
end

include_recipe "bigbluebutton::sounds"

{ "external.xml" => "/opt/freeswitch/etc/freeswitch/sip_profiles/external.xml" }.each do |k,v|
  cookbook_file v do
    source k
    group "daemon"
    owner "freeswitch"
    mode "0640"
    notifies :run, "execute[restart bigbluebutton]", :delayed
  end
end

template "/opt/freeswitch/etc/freeswitch/vars.xml" do
  source "vars.xml.erb"
  group "daemon"
  owner "freeswitch"
  mode "0640"
  variables(
    lazy {{ :external_ip => node['bbb']['external_ip'] == node['bbb']['internal_ip']? "auto-nat": node['bbb']['external_ip'],
            :sound_prefix => node['bbb']['freeswitch']['sounds']['prefix'] }}
  )
  notifies :run, "execute[restart bigbluebutton]", :delayed
end

remote_directory "/etc/nginx/ssl" do
  files_mode '0600'
  source "ssl"
end

execute "generate diffie-hellman parameters" do
  dhp_file = "/etc/nginx/ssl/#{node['bbb']['ssl']['certificates']['dhparam_file']}"
  command "openssl dhparam -out #{dhp_file} 2048"
  only_if { node['bbb']['ssl']['enabled'] }
  creates dhp_file
end

service "nginx"

ruby_block "update nginx server_names_hash" do
  block do
    filepath = "/etc/nginx/nginx.conf"
    if File.exist?(filepath)
      fe = Chef::Util::FileEdit.new(filepath)
      fe.search_file_replace_line(/.*server_names_hash_bucket_size [0-9].*/, "        server_names_hash_bucket_size 64;")
      fe.write_file
    end
  end
  notifies :reload, "service[nginx]", :immediately
end

template "/etc/nginx/sites-available/bigbluebutton" do
  source "bigbluebutton.nginx.erb"
  mode "0644"
  variables(
    lazy {{
      :domain => node['bbb']['server_domain'],
      :secure => node['bbb']['ssl']['enabled'],
      :certificate_file => node['bbb']['ssl']['certificate_file'],
      :certificate_key_file => node['bbb']['ssl']['certificate_key_file'],
      :dhparam_file => node['bbb']['ssl']['certificates']['dhparam_file']
    }}
  )
  notifies :reload, "service[nginx]", :immediately
end

package "bbb-demo" do
  if node['bbb']['demo']['enabled']
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

{ "bbb-check" => node['bbb']['check']['enabled'],
  "bbb-webhooks" => node['bbb']['webhooks']['enabled'],
  "bbb-html5" => node['bbb']['html5']['enabled'] }.each do |pkg, enabled|
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

ruby_block "configure recording workflow" do
    block do
        Dir.glob("/usr/local/bigbluebutton/core/scripts/process/*.rb*").each do |filename|
          format = File.basename(filename).split(".")[0]
          if node['bbb']['recording']['playback_formats'].split(",").include? format
            Chef::Log.info("Enabling record and playback format #{format}");
            command_execute("bbb-record --enable #{format}")
          else
            Chef::Log.info("Disabling record and playback format #{format}");
            command_execute("bbb-record --disable #{format}")
          end
        end
    end
end

[   "/usr/share/red5/webapps/bigbluebutton/WEB-INF/classes/logback-bigbluebutton.xml",
    "/usr/share/red5/webapps/deskshare/WEB-INF/classes/logback-deskshare.xml",
    "/usr/share/red5/webapps/sip/WEB-INF/classes/logback-sip.xml",
    "/usr/share/red5/webapps/video/WEB-INF/classes/logback-video.xml" ].each do |filename|
  ruby_block "set log duration for #{filename}" do
    block do
      expr = "//rollingPolicy[@class='ch.qos.logback.core.rolling.TimeBasedRollingPolicy']/MaxHistory"
      max_history = node['bbb']['logs_max_history']
      restart_required = false
      
      if File.exist? filename
        doc = Nokogiri::XML(File.open(filename))
        nodes = doc.xpath(expr)
        
        if nodes.length > 0
          nodes.each do |node|
            if node.content.to_i != max_history
              Chef::Log.info "Changing log MaxHistory from #{node.content.to_i} to #{max_history} on #{filename}"
              node.content = max_history

              xml_file = File.new(filename, "w")
              xml_file.write(doc.to_xml(:indent => 2))
              xml_file.close
              
              restart_required = true
            end
          end
        end
      end
      
      if restart_required
        self.notifies :run, "execute[restart bigbluebutton]", :delayed
        self.resolve_notification_references
      end
    end
  end
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
  command "bbb-conf --setsalt #{node['bbb']['salt']}"
  action :nothing
  notifies :run, "execute[restart bigbluebutton]", :delayed
end

execute "set bigbluebutton ip" do
  user "root"
  command lazy { "bbb-conf --setip #{node['bbb']['server_domain']}" }
  ignore_failure node['bbb']['ignore_restart_failure']
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
  # use --restart instead of --clean so it keeps the logs
  command "bbb-conf --restart"
  ignore_failure node['bbb']['ignore_restart_failure']
  action :nothing
end

node['bbb']['recording']['rebuild'].each do |record_id|
  execute "rebuild recording" do
    user "root"
    command "bbb-record --rebuild #{record_id}"
    action :run
  end
end
node.set['bbb']['recording']['rebuild'] = []

[ "sip.nginx", "sip-secure.nginx"] .each do |conf_nginx|
  template conf_nginx do
    path "/etc/bigbluebutton/nginx/#{conf_nginx}"
    source "#{conf_nginx}.erb"
    mode "0644"
    variables(
      lazy {{ :external_ip => node['bbb']['external_ip'] }}
    )
    notifies :reload, "service[nginx]", :immediately
  end
end

ruby_block "reset flag restart" do
  block do
    node.set['bbb']['force_restart'] = false
  end
  only_if do node['bbb']['force_restart'] end
  notifies :run, "execute[restart bigbluebutton]", :delayed
end


ruby_block "reset flag setsalt" do
  block do
    node.set['bbb']['enforce_salt'] = nil
    node.set['bbb']['setsalt_needed'] = false
  end
  only_if do node['bbb']['setsalt_needed'] end
  notifies :run, "execute[set bigbluebutton salt]", :delayed
end

ruby_block "reset flag setip" do
  block do
    node.set['bbb']['setip_needed'] = false
  end
  only_if do node['bbb']['setip_needed'] end
  notifies :run, "execute[set bigbluebutton ip]", :delayed
end

# in case we have a cookbook_file to be the default presentation
cookbook_file "/var/www/bigbluebutton-default/default.pdf" do
  source node['bbb']['default_presentation']
  owner "root"
  group "root"
  mode "0644"
  ignore_failure true
end

cookbook_file "/usr/local/bigbluebutton/core/scripts/clean-recordings-data.rb" do
  source "clean-recordings-data.rb"
  owner "root"
  group "root"
  mode "0755"
end

cron "clean-recordings-data-cron" do
  action node['bbb']['clean_recordings_data']['enabled']? :create : :delete 
  hour "2"
  minute "0"
  command "/usr/local/bigbluebutton/core/scripts/clean-recordings-data.rb"
end
