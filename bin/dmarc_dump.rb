#!/usr/bin/env ruby

# = dmarc_dump.rb
#
# Author::    Dirk Meyer
# Copyright:: Copyright (c) 2023 Dirk Meyer
# License::   Distributes under the same terms as Ruby
# SPDX-FileCopyrightText: 2023 Dirk Meyer
# SPDX-License-Identifier: Ruby
#
# Parse an DMARC report XML file and print it in JSON
# Input: xmlfile with  DMARC report
# Output: formatted JSON text
#

require 'nokogiri'
require 'csv'

$: << 'lib'

require 'xmltohash'

# read and print xml file
def run_xml( fullname )
  p fullname
  raw = File.read( fullname )
  return if raw.empty?
  return if raw == 'unused'

  begin
    h = Hash.from_xml( raw )
  rescue NoMethodError
    warn "Bad XML in #{fullname}"
    pp 'raw'
    return
  end
  pp h
  # AOL can send empty XML files
  nil if h.nil?
end

ARGV.each do |arg|
  run_xml( arg )
end

exit 0
# eof
