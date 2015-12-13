#
# Cookbook Name:: bigbluebutton
# Recipe:: install-applet
# Author:: Felipe Cecagno (<felipe@mconf.org>)
#
# This file is part of the Mconf project.
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

cookbook_file "/var/www/bigbluebutton/client/bbb-deskshare-applet-0.9.0.jar" do
    source "bbb-deskshare-applet-0.9.0.jar"
    mode "0644"
    ignore_failure true
end
