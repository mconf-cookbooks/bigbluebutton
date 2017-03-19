#
# Library:: default
# Author:: Felipe Cecagno (<felipe@mconf.org>)
#
# This file is part of the Mconf project.
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

require 'digest/sha1'
require 'net/http'
require 'json'
require 'uri'

module BigBlueButton
  # Helpers for BigBlueButton
  module Helpers
    def command_execute(command, fail_on_error = false)
      process = {}
      process[:status] = Open4::popen4(command) do | pid, stdin, stdout, stderr|
          process[:output] = stdout.readlines
          process[:errors] = stderr.readlines
      end
      if fail_on_error and not process[:status].success?
        raise "Execution failed: #{Array(process[:errors]).join()}"
      end
      process
    end

    def bigbluebutton_packages_version
      packages = [ "bbb-*", node[:bbb][:bigbluebutton][:package_name] ]
      packages_version = {}
      packages.each do |pkg|
        output = `dpkg -l | grep "#{pkg}"`
        output.split("\n").each do |entry|
          entry = entry.split()
          packages_version[entry[1]] = entry[2]
        end
      end
      packages_version
    end

    def is_running_meetings?
      begin
        params = "random=#{rand(99999)}"
        checksum = Digest::SHA1.hexdigest "getMeetings#{params}#{node[:bbb][:salt]}"
        url = URI.parse("http://localhost:8080/bigbluebutton/api/getMeetings?#{params}&checksum=#{checksum}")
        req = Net::HTTP::Get.new(url.to_s)
        res = Net::HTTP.start(url.host, url.port) { |http|
          http.request(req)
        }
        if res.body.include? "<returncode>SUCCESS</returncode>" and not res.body.include? "<messageKey>noMeetings</messageKey>"
          return true
        else
          return false
        end
      rescue
        Chef::Log.fatal("Cannot access the BigBlueButton API")
        return false
      end
    end

    def dns_query(server_domain, opt = {})
      qname = server_domain
      resolve = Dnsruby::Resolver.new(opt)
      ip = nil
      begin
        resolve.query(qname).answer.rrset(qname, Dnsruby::Types.A).rrs.each do |rss|
          address = rss.address
          if address.class == Dnsruby::IPv4
            ip = address.to_s
            break
          end
        end
      rescue
        return nil
      end
      return ip
    end

    def get_external_ip(server_domain)
      dns_query(server_domain, {:nameserver => '8.8.8.8'})
    end
    
    def get_internal_ip()
      ip = Socket.ip_address_list.detect{ |intf| intf.ipv4_private? }
      # if there's no private ipv4 we return any other ipv4 different than loopback
      ip = Socket.ip_address_list.detect{ |intf| intf.ipv4? && ! intf.ipv4_loopback? } if ip.nil?
      ip.ip_address
    end
    
    def get_installed_bigbluebutton_packages(repo)
      hostname = URI.parse(repo).hostname
      
      a = `grep -e "^Package: " -e "^Version: " /var/lib/apt/lists/#{hostname}*-amd64_Packages`.split("\n").collect{ |x| x.sub(/^Package: |^Version: /, "") }
      Hash[a.each_slice(2).to_a]
    end
    
    def get_installed_packages
      `dpkg --get-selections | grep -v deinstall`.split().reject {|x| x == "install"}
    end
    
    def get_bigbluebutton_dependencies(package_name)
      deps = `apt-rdepends #{package_name} | grep -E '^[^ ]'`.split("\n")
      auto = `apt-mark showauto`.split("\n")
      Hash[deps.collect!{ |pkg| [ pkg, auto.include?(pkg) ? :auto : :manual ] }]
    end

    def get_listen_ip(port)
      command = "netstat -ln | grep '^tcp ' | grep ':#{port}' | awk '{ print $4 }' | cut -d: -f1"
      `#{command}`.strip
    end

    def get_freeswitch_listen_ip()
      listen_ip = get_listen_ip(5060)
      listen_ip = node['bbb']['external_ip'] if listen_ip.to_s.empty? 
      listen_ip
    end

    def get_freeswitch_websocket_listen_ip()
      port = 7443 if node['bbb']['ssl']['enabled'] else 5066
      listen_ip = get_listen_ip(port)
      listen_ip = node['bbb']['external_ip'] if listen_ip.to_s.empty? 
      listen_ip
    end
    
    def compare_and_replace_file(new_file, old_file, notifies_restart = false)
      if ! FileUtils.identical?(new_file, old_file)
        if notifies_restart
          self.notifies :run, "execute[restart bigbluebutton]"
          self.resolve_notification_references
        end
        FileUtils.cp new_file, "#{old_file}.#{Time.now.strftime('%Y%m%d%H%M%S')}"
        FileUtils.cp new_file, old_file
      end
    end
    
    def save_xml(xml_filename, doc, notifies_restart = false)
      new_xml_filename = "/tmp/#{File.basename(xml_filename)}"
      xml_file = File.new(new_xml_filename, "w")
      xml_file.write(doc.to_xml(:indent => 2))
      xml_file.close
      compare_and_replace_file(new_xml_filename, xml_filename, notifies_restart)
    end
  end
end

Chef::Recipe.send(:include, ::BigBlueButton::Helpers)
Chef::Resource.send(:include, ::BigBlueButton::Helpers)
Chef::Provider.send(:include, ::BigBlueButton::Helpers)

class Chef
  class Node
    class ImmutableMash
      def to_hash
        h = {}
        self.each do |k,v|
          if v.respond_to?('to_hash')
            h[k] = v.to_hash
          elsif v.respond_to?('each')
            h[k] = []
            v.each do |i|
              if i.respond_to?('to_hash')
                h[k].push(i.to_hash)
              else
                h[k].push(i)
              end
            end
          else
            h[k] = v
          end
        end
        return h
      end
    end
  end
end
