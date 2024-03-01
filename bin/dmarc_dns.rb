#!/usr/bin/env ruby

# = dmarc_dns.rb
#
# Author::    Dirk Meyer
# Copyright:: Copyright (c) 2020 - 2023 Dirk Meyer
# License::   Distributes under the same terms as Ruby
# SPDX-FileCopyrightText: 2020-2023 Dirk Meyer
# SPDX-License-Identifier: Ruby
#
# Maintain a DNS cache for IPs of Mail-servers
# Input: dmarc-report.csv
# Output: dmarc-dns.json
#

require 'resolv'
require 'ipaddr'
require 'json'
require 'csv'

# input file in CSV format
INPUT_FILE = 'dmarc-report.csv'.freeze
# output file in JSON format
DNS_CACHE_FILE = 'dmarc-dns.json'.freeze

# get ptr from host command (bind9)
def get_dns_host( ip )
  result = nil
  `host '#{ip}'`.split( "\n" ).each do |line|
    return 'not found' if line =~ /not found/
    return line.split( /\s/ ).last if line =~ /domain name pointer/

    result = line
  end
  result
end

# get ptr from DNS resolver
def getname_save( ip )
  Resolv.getname( ip ).to_s
rescue Resolv::ResolvError
  'not found'
end

# get ptr for IP
def get_dns( ip )
  return 'not found' if ip == ''
  return 'not found' if ip.nil?

  # return get_dns_host( ip )
  getname_save( ip )
end

# get ptr from cache
def get_cached_dns( ip )
  return @dns_cache[ ip ] if @dns_cache.key?( ip )

  @dns_cache[ ip ] = get_dns( ip )
end

# load json file
def load_json( filename )
  return {} unless File.exist?( filename )

  JSON.parse( File.read( filename ) )
end

# load cache file
def load_cache
  @dns_cache = load_json( DNS_CACHE_FILE )
end

# save cache file
def save_cache
  File.write( DNS_CACHE_FILE, "#{JSON.dump( @dns_cache )}\n" )
end

# parse CSV for source ips
def run_csv
  return unless File.exist?( INPUT_FILE )

  CSV.foreach( INPUT_FILE, encoding: 'UTF-8', col_sep: ';' ) do |row|
    ip = row[ 2 ]
    next if ip == 'source_ip'

    get_cached_dns( ip )
  end
end

# check arguments
ARGV.each do |option|
  case option
  when 'test' # diagnostics
    ARGV.shift
    ip = ARGV.shift
    p get_dns( ip )
    exit 0
  else
    warn "Fehler #{option}"
    exit 65
  end
end

load_cache
run_csv
save_cache

exit 0
# eof
