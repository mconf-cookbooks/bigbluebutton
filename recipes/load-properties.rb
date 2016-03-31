#
# Cookbook Name:: bigbluebutton
# Recipe:: load-properties
# Author:: Felipe Cecagno (<felipe@mconf.org>)
# Author:: Mauricio Cruz (<brcruz@gmail.com>)
#
# This file is part of the Mconf project.
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

require 'socket'
require 'securerandom'
require 'ipaddress'

ruby_block "define bigbluebutton properties" do
    block do
        properties = Hash[File.read("/var/lib/tomcat7/webapps/bigbluebutton/WEB-INF/classes/bigbluebutton.properties", :encoding => "UTF-8").scan(/(.+?)=(.+)/)]
        if properties.nil? or properties.empty?
            Chef::Log.info("bigbluebutton.properties exists but it's empty")
            return
        end
        
        protocol = node['bbb']['ssl']['enabled']? "https": "http"
        ip = node['bbb']['ip']
        server_addr = node['ipaddress']
        if not ip.nil? and not ip.empty?
            server_addr = ip.gsub(/(http:\/\/)|(https:\/\/)/, "")
        end
        server_url = "#{protocol}://#{server_addr}"
        server_domain = server_addr.split(":")[0]

        node.default['bbb']['ip'] = ip
        node.default['bbb']['server_addr'] = server_addr
        node.default['bbb']['server_url'] = server_url
        node.default['bbb']['server_domain'] = server_domain
        node.default['bbb']['internal_ip'] = node['ipaddress']

        external_ip = get_external_ip(node['bbb']['server_domain'])
        if external_ip.to_s == ''
            external_ip = node['bbb']['internal_ip']
        end
        node.default['bbb']['external_ip'] = external_ip

        if properties["securitySalt"].to_s == ''
            node.default['bbb']['salt'] = SecureRandom.hex(16)
        else
            node.default['bbb']['salt'] = properties["securitySalt"]
        end

        set_salt = node['bbb']['salt'] != properties["securitySalt"]
        set_ip = node['bbb']['server_url'] != properties["bigbluebutton.web.serverURL"]
        self.notifies :run, "execute[set bigbluebutton salt]" if set_salt
        self.notifies :run, "execute[set bigbluebutton ip]" if set_ip

        node.save unless Chef::Config['solo']

        node.default['bbb']['handling_meetings'] = is_running_meetings?

        Chef::Log.info("\tserver_url       : #{node['bbb']['server_url']}")
        Chef::Log.info("\tserver_addr      : #{node['bbb']['server_addr']}")
        Chef::Log.info("\tserver_domain    : #{node['bbb']['server_domain']}")
        Chef::Log.info("\tinternal_ip      : #{node['bbb']['internal_ip']}")
        Chef::Log.info("\texternal_ip      : #{node['bbb']['external_ip']}")
        Chef::Log.info("\tsalt             : #{node['bbb']['salt']}")
        Chef::Log.info("\t--salt?          : #{set_salt}")
        Chef::Log.info("\t--setip?         : #{set_ip}")
        Chef::Log.info("\thandling_meetings: #{node['bbb']['handling_meetings']}")

        self.resolve_notification_references
    end
    action :run
    only_if { File.exists? '/var/lib/tomcat7/webapps/bigbluebutton/WEB-INF/classes/bigbluebutton.properties' }
end
