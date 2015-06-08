#
# Cookbook Name:: bigbluebutton
# Recipe:: ffmpeg
# Author:: Felipe Cecagno (<felipe@mconf.org>)
#
# This file is part of the Mconf project.
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

node[:bbb][:ffmpeg][:dependencies].each do |pkg|
  package pkg
end

if node[:bbb][:ffmpeg][:install_method] == "package"
  current_ffmpeg_version = `ffmpeg -version | grep 'ffmpeg version' | cut -d' ' -f3`.strip!
  ffmpeg_update_needed = (current_ffmpeg_version != node[:bbb][:ffmpeg][:version])
  ffmpeg_dst = "/tmp/#{node[:bbb][:ffmpeg][:filename]}"

  remote_file ffmpeg_dst do
    source "#{node[:bbb][:ffmpeg][:repo_url]}/#{node[:bbb][:ffmpeg][:filename]}"
    action :create
    only_if { ffmpeg_update_needed }
  end

  dpkg_package "ffmpeg" do
    source ffmpeg_dst
    action :install
    only_if { ffmpeg_update_needed }
  end
else
  # dependencies of libvpx and ffmpeg
  # https://code.google.com/p/bigbluebutton/wiki/090InstallationUbuntu#3.__Install_ffmpeg
  %w( build-essential git-core checkinstall yasm texi2html libvorbis-dev 
      libx11-dev libxfixes-dev zlib1g-dev pkg-config netcat ).each do |pkg|
    package pkg do
      action :install
    end
  end

  ffmpeg_repo = "#{Chef::Config[:file_cache_path]}/ffmpeg"

  execute "set ffmpeg version" do
    command "cp #{ffmpeg_repo}/RELEASE #{ffmpeg_repo}/VERSION"
    action :nothing
    subscribes :run, "git[#{ffmpeg_repo}]", :immediately
  end

  # ffmpeg already includes libvpx
  include_recipe "ffmpeg"
end

if node[:bbb][:libvpx][:install_method] == "package"
  libvpx_dst = "/tmp/#{node[:bbb][:libvpx][:filename]}"

  remote_file libvpx_dst do
    source "#{node[:bbb][:libvpx][:repo_url]}/#{node[:bbb][:libvpx][:filename]}"
    action :create_if_missing
  end

  dpkg_package "libvpx" do
    source libvpx_dst
    action :install
  end
else
  if node[:bbb][:ffmpeg][:install_method] == "source"
    # do nothing because ffmpeg already installed libvpx
  else
    include_recipe "libvpx::source"
  end
end
