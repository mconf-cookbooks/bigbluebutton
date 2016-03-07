#!/usr/bin/ruby
# encoding: UTF-8

require 'fileutils'
require 'logger'
require 'rubygems'

def clear(record_id, originator)
  match = /\w+-\d+/.match record_id
  if match.nil?
    $logger.info "Invalid record_id #{record_id} read from #{originator}"
    return
  end
  output = []

  # presentations
  output += Dir.glob("/var/bigbluebutton/#{record_id}")
  # webcam streams in red5
  output += Dir.glob("/usr/share/red5/webapps/video/streams/#{record_id}")
  # desktop sharing streams in red5
  output += Dir.glob("/var/bigbluebutton/deskshare/#{record_id}-*.flv")
  # FreeSWITCH wav recordings
  output += Dir.glob("/var/freeswitch/meetings/#{record_id}-*.wav")

  $logger.info "Found files to remove because of #{originator}" if ! output.empty?

  output.each do |file_or_dir|
    # if the raw directory is there for the particular meeting, we check if the content archived is identical to the content to be deleted
    if Dir.exists? "/var/bigbluebutton/recording/raw/#{record_id}"
      files_to_test = File.file?(file_or_dir) ? [ file_or_dir ] : Dir.entries(file_or_dir).select { |f| File.file? f }
      skip = false
      files_to_test.each do |file_to_test|
        potentials = Dir.glob("/var/bigbluebutton/recording/raw/#{record_id}/**/#{File.basename(file_to_test)}")
        potentials.select! { |f| FileUtils.identical?(file_to_test, f) }
        if potentials.empty?
          $logger.info ".... Not removing #{file_to_test} because it couldn't be verified"
          skip = true
          break
        end
      end
      next if skip
    end
    $logger.info ".... Removing #{file_or_dir}"
    
    FileUtils.rm_rf(file_or_dir)
  end
end

$logger = Logger.new("/var/log/bigbluebutton/clean-recordings-data.log")
$logger.level = Logger::INFO

Dir.glob("/var/bigbluebutton/recording/status/archived/*.norecord").each do |archived_norecord|
  match = /([^\/]*).norecord$/.match(archived_norecord)
  record_id = match[1]
  clear(record_id, archived_norecord)
end

Dir.glob("/var/bigbluebutton/recording/status/published/*.done").each do |published|
  match = /(.*)-.*/.match File.basename(published)
  record_id = match[1]
  clear(record_id, published)
end
