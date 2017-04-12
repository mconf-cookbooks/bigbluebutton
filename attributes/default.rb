#
# This file is part of the Mconf project.
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

default['bbb']['bigbluebutton']['repo_url'] = "http://ubuntu.bigbluebutton.org/trusty-090"
default['bbb']['bigbluebutton']['key_url'] = "http://ubuntu.bigbluebutton.org/bigbluebutton.asc"
default['bbb']['bigbluebutton']['dist'] = "trusty"
default['bbb']['bigbluebutton']['components'] = ["bigbluebutton-trusty" , "main"]
default['bbb']['bigbluebutton']['package_name'] = "bigbluebutton"
default['bbb']['bigbluebutton']['upgrade_dependencies'] = true

default['bbb']['recording']['rebuild'] = []
default['bbb']['recording']['playback_formats'] = "presentation"
default['bbb']['recording']['playback_copyright'] = nil
default['bbb']['recording']['playback_unavailable'] = nil
default['bbb']['recording']['playback_title'] = nil
default['bbb']['demo']['enabled'] = false
default['bbb']['check']['enabled'] = false
default['bbb']['webhooks']['enabled'] = true
default['bbb']['html5']['enabled'] = false
default['bbb']['ip'] = nil
default['bbb']['force_restart'] = false
default['bbb']['enforce_salt'] = nil
default['bbb']['keep_files_newer_than'] = 5
default['bbb']['default_presentation'] = "default.pdf"
default['bbb']['logs_max_history'] = 30
default['bbb']['recording_raw_retention']['remove_old_recordings'] = false
default['bbb']['recording_raw_retention']['max_retention'] = 365
default['bbb']['recording_raw_retention']['logrotate']['frequency'] = 'monthly'
default['bbb']['recording_raw_retention']['logrotate']['rotate'] = 6
default['bbb']['recording_raw_retention']['logrotate']['size'] = nil
default['bbb']['clean_recordings_data']['enabled'] = false
default['bbb']['ignore_restart_failure'] = false
default['bbb']['default_video_quality'] = "medium"
default['bbb']['stun_servers'] = [ "stun.l.google.com:19302", "stun1.l.google.com:19302", "stun2.l.google.com:19302", "stun3.l.google.com:19302", "stun4.l.google.com:19302" ]
# use this to artificially add ice candidates to the remote SDP
default['bbb']['remote_ice_candidates'] = []

default['bbb']['ssl']['enabled'] = false
# see http://docs.bigbluebutton.org/install/install.html#configure-nginx-http
default['bbb']['ssl']['certificates']['certificate_file'] = ""       # .crt
default['bbb']['ssl']['certificates']['certificate_key_file'] = ""   # .key
default['bbb']['ssl']['certificates']['dhparam_file'] = "dhp-2048.pem"

# logrotate options
# by default keeps one log file per day, during a week
default['bbb']['logrotate']['frequency'] = 'daily'
default['bbb']['logrotate']['rotate']    = 7
default['bbb']['logrotate']['size']      = nil

default['x264']['install_method'] = :none
default['libvpx']['install_method'] = :package
default['ffmpeg']['install_method'] = :source
default['ffmpeg']['git_repository'] = "https://github.com/FFmpeg/FFmpeg.git"
default['ffmpeg']['git_revision'] = "n2.3.3"
default['ffmpeg']['compile_flags'] = [ "--enable-version3",
                                       "--enable-postproc",
                                       "--enable-libvorbis",
                                       "--enable-libvpx" ]

default['bbb']['freeswitch']['sounds']['dir'] = "/opt/freeswitch/share/freeswitch/sounds"
default['bbb']['freeswitch']['sounds']['repo'] = "http://files.freeswitch.org/releases/sounds"
default['bbb']['freeswitch']['sounds']['frequency'] = [ "48000", "32000", "16000", "8000" ]
default['bbb']['freeswitch']['sounds']['name_version'] = {}
default['bbb']['freeswitch']['sounds']['prefix'] = "$${sounds_dir}/en/us/callie"
default['bbb']['freeswitch']['sounds']['profile'] = {
                                       "muted-sound" => "",
                                       "unmuted-sound" => "",
                                       "alone-sound" => "",
                                       "moh-sound" => "",
                                       "comfort-noise" => "false"
                                       }

# set to external_ip or internal_ip
default['bbb']['freeswitch']['interface'] = "external_ip"
