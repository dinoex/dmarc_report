#!/usr/bin/env ruby

# = dmarc_report.rb
#
# Author::    Dirk Meyer
# Copyright:: Copyright (c) 2020 - 2023 Dirk Meyer
# License::   Distributes under the same terms as Ruby
# SPDX-FileCopyrightText: 2020-2023 Dirk Meyer
# SPDX-License-Identifier: Ruby
#
# Parse directory with DMARC reports and extract the attachments
# Input: directory with extracted XML attachments
# Output: summary reports as CSV file
#

require 'nokogiri'
require 'csv'

$: << 'lib'

require 'xmltohash'

# directory with extracted XML attachments
XML_DIR = 'DMARC/xml'.freeze
# summary reports as CSV file
OUTPUT_FILE = 'dmarc-report.csv'.freeze

# convert tiemstamp to short ISO date
def date_text( secs )
  Time.at( secs.to_i ).strftime( '%Y-%m-%d' )
end

# generate csv header
def titles
  [ :ziel_server, :datum, :source_ip, :header_from, :envelope_to, :anzahl,
    :dkim, :dkim_ergebnis, :spf, :spf_ergebnis, :local_policy ].map( &:to_s )
end

# parse auth_results entry
def auth_results_entry( entry, header_from )
  if entry.key?( :domain )
    entry[ :domain ]&.downcase!
    return entry[ :result ] if entry[ :domain ] == header_from

    return "#{entry[ :result ]}:#{entry[ :domain ]}"
  end
  return "#{entry[ :result ]}:#{entry[ :scope ]}" if entry.key?( :scope )

  entry[ :result ]
end

# search auth_results
def auth_results_field( record, field, header_from )
  return nil unless record[ :auth_results ].respond_to?( :key? )
  return nil unless record[ :auth_results ].key?( field )

  return auth_results_entry( record[ :auth_results ][ field ], header_from ) \
    if record[ :auth_results ][ field ].respond_to?( :key? )

  list = []
  record[ :auth_results ][ field ].each do |entry|
    list.push( auth_results_entry( entry, header_from ) )
  end
  list.join( ' ' )
end

# search for arc results
def local_results( hash )
  return nil if hash.nil?
  return nil unless hash.key?( :type )
  return hash[ :type ] if hash[ :type ] == 'mailing_list'
  return "type=#{hash[ :type ]}" if hash[ :type ] != 'local_policy'
  return hash[ :type ] unless hash.key?( :comment )
  return hash[ :type ] if hash[ :comment ].nil?

  hash[ :comment ]
end

# add cvs row
def add_row( hash, record )
  # pp record
  pp record
  header_from = record[ :identifiers ][ :header_from ]
  header_from&.downcase!
  @log.push( [
              hash[ :feedback ][ :report_metadata ][ :email ].split( '@' ).last,
              date_text( hash[ :feedback ][ :report_metadata ][ :date_range ][ :begin ] ),
              record[ :row ][ :source_ip ],
              header_from,
              record[ :identifiers ][ :envelope_to ],
              record[ :row ][ :count ].to_i,
              record[ :row ][ :policy_evaluated ][ :dkim ],
              auth_results_field( record, :dkim, header_from ),
              record[ :row ][ :policy_evaluated ][ :spf ],
              auth_results_field( record, :spf, header_from ),
              local_results( record[ :row ][ :policy_evaluated ][ :reason ] )
            ] )
  pp @log.last
end

# parse xml file
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
  return if h.nil?

  records = h[ :feedback ][ :record ]
  # pp records
  if records.respond_to?( :key? )
    add_row( h, records )
    return
  end
  records.each do |record|
    add_row( h, record )
  end
end

# parse xml directory
def parse_xml_dir
  Dir.entries( XML_DIR ).each do |file|
    fullname = "#{XML_DIR}/#{file}"
    case file
    when /^[.]/
      next
    when /[.]xml$/, /[.]xml_[0-9]*$/
      run_xml( fullname )
      next
    end
    p fullname
    puts 'Aborted extension'
    exit 1
  end
end

@log = []
parse_xml_dir
# pp @log

# write csv
@log.sort_by! { |r| r[ 1 ] }
CSV.open( OUTPUT_FILE, 'wb+', col_sep: ';' ) do |csv|
  csv << titles
  @log.each do |row|
    csv << row
  end
end

exit 0
# eof
