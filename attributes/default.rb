#
# This file is part of the Mconf project.
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

default['bbb']['bigbluebutton']['repo_url'] = "http://ubuntu.bigbluebutton.org/trusty-090"
default['bbb']['bigbluebutton']['key_url'] = "http://ubuntu.bigbluebutton.org/bigbluebutton.asc"
default['bbb']['bigbluebutton']['components'] = ["bigbluebutton-trusty" , "main"]
default['bbb']['bigbluebutton']['package_name'] = "bigbluebutton"

default['bbb']['recording']['rebuild'] = []
default['bbb']['recording']['playback_formats'] = "presentation"
default['bbb']['demo']['enabled'] = false
default['bbb']['check']['enabled'] = false
default['bbb']['webhooks']['enabled'] = true
default['bbb']['html5']['enabled'] = false
default['bbb']['ip'] = nil
default['bbb']['force_restart'] = false
default['bbb']['enforce_salt'] = nil
default['bbb']['keep_files_newer_than'] = 5
default['bbb']['default_presentation'] = "default.pdf"

default['x264']['install_method'] = :none
default['libvpx']['install_method'] = :package
default['ffmpeg']['install_method'] = :source
default['ffmpeg']['install_method'] = :source
default['ffmpeg']['git_repository'] = "https://github.com/FFmpeg/FFmpeg.git"
default['ffmpeg']['git_revision'] = "n2.3.3"
default['ffmpeg']['compile_flags'] = [ "--enable-version3",
                                       "--enable-postproc",
                                       "--enable-libvorbis",
                                       "--enable-libvpx" ]
