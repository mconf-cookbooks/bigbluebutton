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

    def get_external_ip(server_domain)
      qname = server_domain
      resolve = Dnsruby::Resolver.new({:nameserver => '8.8.8.8'})
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
    
    def get_installed_bigbluebutton_packages(repo)
      hostname = URI.parse(repo).hostname
      
      a = `grep -e "^Package: " -e "^Version: " /var/lib/apt/lists/#{hostname}*-amd64_Packages`.split("\n").collect {|x| x.sub(/^Package: |^Version: /, "")}
      Hash[a.each_slice(2).to_a]
    end
    
    def get_installed_packages
      `dpkg --get-selections | grep -v deinstall`.split().reject {|x| x == "install"}
    end
  end
end

Chef::Recipe.send(:include, ::BigBlueButton::Helpers)
Chef::Resource.send(:include, ::BigBlueButton::Helpers)
Chef::Provider.send(:include, ::BigBlueButton::Helpers)
