#
# Recipe:: open4
# Author:: Felipe Cecagno (<felipe@mconf.org>)
#
#
# This file is part of the Mconf project.
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

gem_prereqs = [ "zlib1g-dev" ]

gem_prereqs.each do |pkg|
  p = package "#{pkg}" do
    action :nothing
  end
  p.run_action(:install)
end

{ "open4" => "1.3.0",
  "dnsruby" => "1.59.2",
  "nokogiri" => "1.6.8" }.each do |gem_name, gem_version|
    chef_gem gem_name do
      version gem_version
      action :install
    end
    
    require gem_name
end
