#!/usr/bin/env ruby

# = dmarc_ripmime.rb
#
# Author::    Dirk Meyer
# Copyright:: Copyright (c) 2020 - 2023 Dirk Meyer
# License::   Distributes under the same terms as Ruby
# SPDX-FileCopyrightText: 2020-2023 Dirk Meyer
# SPDX-License-Identifier: Ruby
#
# Parse directory with DMARC reports and extract the attachments
# Input: file with mail
# Output: decompressed attachments
#

# dependecies:
# apt-get install ripmime

# directory with new reports
INPUT_DIR = 'DMARC/in'.freeze
# directory with processed reports
SEEN_DIR = 'DMARC/seen'.freeze
# directory with new attachments
RIPMIME_DIR = 'DMARC/ripmime'.freeze
# directory with processed attachments
ZIP_DIR = 'DMARC/zips'.freeze
# directory with extracted attachments
XML_DIR = 'DMARC/xml'.freeze
# working directory for unzip
TMP_DIR = 'DMARC/tmp'.freeze

# start ripmime
def run_ripmime( src, dest )
  line = "ripmime -i '#{src}' -d '#{RIPMIME_DIR}'"
  rc = system( line )
  if rc
    # puts "mv '#{src}' '#{dest}'"
    File.rename( src, dest )
    return
  end
  warn 'ABORTED: ripmime'
  exit 1
end

# search for new reports
def parse_input_dir
  Dir.entries( INPUT_DIR ).each do |file|
    next if file =~ /^[.]/

    fullname = "#{INPUT_DIR}/#{file}"
    target = "#{SEEN_DIR}/#{file}"
    p fullname
    run_ripmime( fullname, target )
  end
end

# search for decompressed XML file
def parse_temp_dir
  list = []
  Dir.entries( TMP_DIR ).each do |file|
    next if file =~ /^[.]/

    list.push( file )
  end
  if list.empty?
    puts 'no xml file found'
    pp list
    exit 1
  end
  if list.size != 1
    puts 'to many xml files:'
    list.each do |file|
      puts "rm #{file}"
      File.unlink( "#{TMP_DIR}/#{file}" )
    end
    exit 1
  end
  list.first
end

# decompress zip attachment
def unzip( fullname, target )
  return if File.exist?( target )

  line = "unzip -j -n -d '#{TMP_DIR}' '#{fullname}'"
  p line
  rc = system( line )
  if rc
    src = "#{TMP_DIR}/#{parse_temp_dir}"
    # puts "mv '#{src}' '#{target}'"
    File.rename( src.to_s, target )
    return
  end
  warn 'ABORTED: unzip'
  exit 1
end

# decompress gzip attachment
def ungzip( fullname, target )
  return if File.exist?( target )

  line = "gunzip -c '#{fullname}' > '#{target}'"
  p line
  rc = system( line )
  return if rc

  p rc
  warn 'ABORTED: gunzip'
  exit 1
end

# search for new attachments
def parse_ripmime_dir
  Dir.entries( RIPMIME_DIR ).each do |file|
    fullname = "#{RIPMIME_DIR}/#{file}"
    saved = "#{ZIP_DIR}/#{file}"
    case file
    when /^[.]/
      next
    when /[.]zip$/
      # target = "#{XML_DIR}/#{file}".sub( /(_[0-9])*[.]zip$/, '.xml' )
      target = "#{XML_DIR}/#{file}".sub( /[.]zip$/, '.xml' )
      unzip( fullname, target )
      File.rename( fullname, saved )
      next
    when /[.]xml(_[0-9])*[.]gz$/
      # target = "#{XML_DIR}/#{file}".sub( /(_[0-9])*[.]gz$/, '' )
      target = "#{XML_DIR}/#{file}".sub( /[.]gz$/, '' )
      ungzip( fullname, target )
      File.rename( fullname, saved )
      next
    when /^textfile/
      File.unlink( fullname )
      next
    end
    puts "IGNORED extension: #{fullname}"
  end
end

parse_input_dir
parse_ripmime_dir

exit 0
# eof
