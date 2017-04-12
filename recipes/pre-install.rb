#
# Cookbook Name:: bigbluebutton
# Recipe:: pre-install
# Author:: Felipe Cecagno (<felipe@mconf.org>)
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
package "wget"
package "apt-rdepends"

# add bigbluebutton repo
apt_repository node['bbb']['bigbluebutton']['package_name'] do
  key node['bbb']['bigbluebutton']['key_url']
  uri node['bbb']['bigbluebutton']['repo_url']
  distribution node['bbb']['bigbluebutton']['dist']
  components node['bbb']['bigbluebutton']['components']
  notifies :run, 'execute[apt-get update]', :immediately
end

