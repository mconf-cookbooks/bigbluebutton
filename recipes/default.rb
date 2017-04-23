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

include_recipe "bigbluebutton::pre-install"

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
      upgrade_list << "libreoffice"

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

ruby_block "update freeswitch config files" do
  block do
    xml_filename = "/opt/freeswitch/etc/freeswitch/vars.xml"
    if File.exists? xml_filename
      doc = Nokogiri::XML(File.open(xml_filename)) { |x| x.noblanks }
      
      # http://docs.bigbluebutton.org/1.1/install.html#audio-not-working
      xml_node = doc.at_xpath("//X-PRE-PROCESS[@cmd='set' and starts-with(@data, 'local_ip_v4=')]")
      xml_node.remove if ! xml_node.nil?
      xml_node = doc.at_xpath("//X-PRE-PROCESS[@cmd='set' and starts-with(@data, 'external_ip_v4=')]")
      xml_node.remove if ! xml_node.nil?

      xml_node = doc.at_xpath("//X-PRE-PROCESS[@cmd='set' and starts-with(@data, 'bind_server_ip=')]")
      xml_node["data"] = "bind_server_ip=#{node['bbb'][node['bbb']['freeswitch']['interface']]}"
      xml_node = doc.at_xpath("//X-PRE-PROCESS[@cmd='set' and starts-with(@data, 'external_rtp_ip=')]")
      xml_node["data"] = "external_rtp_ip=#{node['bbb'][node['bbb']['freeswitch']['interface']]}"
      xml_node = doc.at_xpath("//X-PRE-PROCESS[@cmd='set' and starts-with(@data, 'external_sip_ip=')]")
      xml_node["data"] = "external_sip_ip=#{node['bbb'][node['bbb']['freeswitch']['interface']]}"

      xml_node = doc.at_xpath("//X-PRE-PROCESS[@cmd='set' and starts-with(@data, 'sound_prefix=')]")
      xml_node["data"] = "sound_prefix=#{node['bbb']['freeswitch']['sounds']['prefix']}"

      save_xml(xml_filename, doc, true)
    end
    
    xml_filename = "/opt/freeswitch/conf/sip_profiles/external.xml"
    if File.exists? xml_filename
      doc = Nokogiri::XML(File.open(xml_filename)) { |x| x.noblanks }

      xml_node = doc.at_xpath("//param[@name='ext-rtp-ip']")
      xml_node["value"] = "$${external_rtp_ip}"

      xml_node = doc.at_xpath("//param[@name='ext-sip-ip']")
      xml_node["value"] = "$${external_sip_ip}"

      xml_node = doc.at_xpath("//param[@name='ws-binding']")
      if node['bbb']['ssl']['enabled']
        xml_node.remove if ! xml_node.nil?
      else
        if xml_node.nil?
          xml_node = Nokogiri::XML::Node.new "param", doc
          xml_node["name"] = "ws-binding"
          xml_node["value"] = ":5066"
          doc.at("/profile/settings") << xml_node
        else
          xml_node["value"] = ":5066"
        end
      end

      xml_node = doc.at_xpath("//param[@name='wss-binding']")
      if node['bbb']['ssl']['enabled']
        if xml_node.nil?
          xml_node = Nokogiri::XML::Node.new "param", doc
          xml_node["name"] = "wss-binding"
          xml_node["value"] = ":7443"
          doc.at("/profile/settings") << xml_node
        else
          xml_node["value"] = ":7443"
        end
      else
        xml_node.remove if ! xml_node.nil?
      end

      save_xml(xml_filename, doc, true)
    end
    
    xml_filename = "/opt/freeswitch/conf/sip_profiles/internal.xml"
    if File.exists? xml_filename
      doc = Nokogiri::XML(File.open(xml_filename)) { |x| x.noblanks }

      xml_node = doc.at_xpath("//param[@name='ws-binding']")
      xml_node.remove if ! xml_node.nil?
      xml_node = doc.at_xpath("//param[@name='wss-binding']")
      xml_node.remove if ! xml_node.nil?

      save_xml(xml_filename, doc, true)
    end

    xml_filename = "/opt/freeswitch/conf/autoload_configs/event_socket.conf.xml"
    if File.exists? xml_filename
      doc = Nokogiri::XML(File.open(xml_filename)) { |x| x.noblanks }

      xml_node = doc.at_xpath("//param[@name='listen-ip']")
      xml_node["value"] = "127.0.0.1"

      save_xml(xml_filename, doc, true)
    end

    xml_filename = "/var/lib/tomcat7/webapps/bigbluebutton/WEB-INF/spring/turn-stun-servers.xml"
    if File.exists? xml_filename
      doc = Nokogiri::XML(File.open(xml_filename)) { |x| x.noblanks }

      doc.xpath("//xmlns:bean[@class='org.bigbluebutton.web.services.turn.StunServer']").each do |xml_node|
        xml_node.remove
      end
      doc.xpath("//xmlns:bean[@class='org.bigbluebutton.web.services.turn.StunTurnService']/xmlns:property[@name='stunServers']/xmlns:set/xmlns:ref").each do |ref|
        ref.remove
      end

      node['bbb']['stun_servers'].each_with_index do |stun_server, index|
        id = "stun#{index+1}"
        bean = Nokogiri::XML::Node.new "bean", doc
        bean["id"] = id
        bean["class"] = "org.bigbluebutton.web.services.turn.StunServer"
        constructor = Nokogiri::XML::Node.new "constructor-arg", doc
        constructor["index"] = "0"
        constructor["value"] = "stun:#{stun_server}"
        bean << constructor
        doc.at("/xmlns:beans") << bean

        ref = Nokogiri::XML::Node.new "ref", doc
        ref["bean"] = id
        doc.at("/xmlns:beans/xmlns:bean[@class='org.bigbluebutton.web.services.turn.StunTurnService']/xmlns:property[@name='stunServers']/xmlns:set") << ref
      end

      doc.xpath("//xmlns:bean[@class='org.bigbluebutton.web.services.turn.RemoteIceCandidate']").each do |xml_node|
        xml_node.remove
      end
      doc.xpath("//xmlns:bean[@class='org.bigbluebutton.web.services.turn.StunTurnService']/xmlns:property[@name='remoteIceCandidates']/xmlns:set/xmlns:ref").each do |ref|
        ref.remove
      end

      node['bbb']['remote_ice_candidates'].each_with_index do |candidate, index|
        id = "iceCandidate#{index+1}"
        bean = Nokogiri::XML::Node.new "bean", doc
        bean["id"] = id
        bean["class"] = "org.bigbluebutton.web.services.turn.RemoteIceCandidate"
        constructor = Nokogiri::XML::Node.new "constructor-arg", doc
        constructor["index"] = "0"
        constructor["value"] = candidate
        bean << constructor
        doc.at("/xmlns:beans") << bean

        ref = Nokogiri::XML::Node.new "ref", doc
        ref["bean"] = id
        doc.at("/xmlns:beans/xmlns:bean[@class='org.bigbluebutton.web.services.turn.StunTurnService']/xmlns:property[@name='remoteIceCandidates']/xmlns:set") << ref
      end

      save_xml(xml_filename, doc, true)
    end
    
    filename = "/usr/share/red5/webapps/sip/WEB-INF/bigbluebutton-sip.properties"
    if File.exists? filename
      new_filename = "/tmp/#{File.basename(filename)}"
      FileUtils.cp filename, new_filename
      freeswitch_ip = get_freeswitch_listen_ip()
      command = "sed -i 's|^bbb.sip.app.ip=.*|bbb.sip.app.ip=#{freeswitch_ip}|g' #{new_filename}"
      `#{command}`
      command = "sed -i 's|^freeswitch.ip=.*|freeswitch.ip=#{freeswitch_ip}|g' #{new_filename}"
      `#{command}`
      compare_and_replace_file(new_filename, filename, true)
    end
    
    xml_filename = "/var/bigbluebutton/playback/presentation/0.9.0/playback.html"
    if File.exists? xml_filename
      doc = Nokogiri::HTML(File.open(xml_filename)) { |x| x.noblanks }
      if ! node['bbb']['recording']['playback_copyright'].nil?
        xml_node = doc.at_xpath("//div[@id='copyright']")
        xml_node.inner_html = node['bbb']['recording']['playback_copyright'] if ! xml_node.nil?
      end
      if ! node['bbb']['recording']['playback_unavailable'].nil?
        xml_node = doc.at_xpath("//p[@id='load-error-msg']")
        xml_node.inner_html = node['bbb']['recording']['playback_unavailable'] if ! xml_node.nil?
      end
      if ! node['bbb']['recording']['playback_title'].nil?
        xml_node = doc.at_xpath("//title")
        xml_node.inner_html = node['bbb']['recording']['playback_title'] if ! xml_node.nil?
      end
      save_xml(xml_filename, doc, false)
    end
  end
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
  notifies :restart, "service[nginx]", :immediately
end

cookbook_file "/var/www/bigbluebutton-default/index.html" do
  source "index.html"
  if node['bbb']['demo']['enabled']
    action :create
  else
    action :delete
  end
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
        new_filename = "/tmp/#{File.basename(filename)}"
        FileUtils.cp filename, new_filename
        
        doc = Nokogiri::XML(File.open(filename)) { |x| x.noblanks }
        nodes = doc.xpath(expr)
        
        nodes.each do |node|
          node.content = max_history
        end
        
        compare_and_replace_file(new_filename, filename, true)
      end
    end
  end
end

execute "restart bigbluebutton" do
  user "root"
  command "echo 'Restarting'"
  action :nothing
  notifies :run, "execute[set bigbluebutton ip]", :delayed
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

template "sip.nginx" do
  path "/etc/bigbluebutton/nginx/sip.nginx"
  source "sip.nginx.erb"
  mode "0644"
  variables(
    lazy {{ :listen_ip => get_freeswitch_websocket_listen_ip(),
            :secure => node['bbb']['ssl']['enabled'] }}
  )
  notifies :reload, "service[nginx]", :immediately
end

cookbook_file "/etc/bigbluebutton/nginx/sip-secure.nginx" do
  action :delete
  notifies :reload, "service[nginx]", :immediately
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

ruby_block "set default video quality" do
  block do
    filename = "/var/www/bigbluebutton/client/conf/profiles.xml"
    if File.exist? filename
      doc = Nokogiri::XML::Document.parse(File.open(filename), nil, "UTF-8")
      default_node = doc.at_xpath("//profile[@id='#{node['bbb']['default_video_quality']}']")
      if ! default_node.nil?
        doc.xpath("//profile[@default='true']").each do |node|
          node.remove_attribute("default")
        end
        default_node["default"] = "true"
        xml_file = File.new(filename, "w")
        xml_file.write(doc.to_xml(:indent => 2))
        xml_file.close
      end
    end
  end
end
