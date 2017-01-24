#
# Cookbook Name:: bigbluebutton
# Recipe:: sounds
# Author:: Felipe Cecagno (<felipe@mconf.com>)
#
# This file is part of the Mconf project.
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

node['bbb']['freeswitch']['sounds']['frequency'].each do |frequency|
  node['bbb']['freeswitch']['sounds']['name_version'].each do |name, version|
    id = "#{name}-#{frequency}-#{version}"
    filename = "#{id}.tar.gz"
    remote_file "#{node['bbb']['freeswitch']['sounds']['dir']}/#{filename}" do
      source "#{node['bbb']['freeswitch']['sounds']['repo']}/#{filename}"
    end

    bash "extract" do
      cwd node['bbb']['freeswitch']['sounds']['dir']
      code <<-EOH
        tar xvf "#{filename}"
        touch "#{id}.done"
        chown -R freeswitch:daemon .
        EOH
      not_if { ::File.exist?("#{node['bbb']['freeswitch']['sounds']['dir']}/#{id}.done") }
    end
  end
end

ruby_block "update sounds" do
  block do
    Dir.chdir("/opt/freeswitch/etc/freeswitch/autoload_configs") do
      FileUtils.cp("conference.conf.xml", "conference.conf.xml.orig")
      node['bbb']['freeswitch']['sounds']['profile'].each do |param_name, param_value|
        `xmlstarlet ed -L -d "/configuration/profiles/profile/param[@name='#{param_name}']" conference.conf.xml`
        if ! param_value.empty?
          `xmlstarlet ed -L -s /configuration/profiles/profile -t elem -n paramTMP -v "" -i //paramTMP -t attr -n "name" -v "#{param_name}" -i //paramTMP -t attr -n "value" -v "#{param_value}" -r //paramTMP -v param conference.conf.xml`
        end
      end
      if ! FileUtils.identical?("conference.conf.xml", "conference.conf.xml.orig")
        self.notifies :run, "execute[restart bigbluebutton]"
        self.resolve_notification_references
      end
      FileUtils.rm_f("conference.conf.xml.orig")
    end
  end
end
