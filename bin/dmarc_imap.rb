#!/usr/bin/env ruby

# = dmarc_imap.rb
#
# Author::    Dirk Meyer
# Copyright:: Copyright (c) 2020 - 2024 Dirk Meyer
# License::   Distributes under the same terms as Ruby
# SPDX-FileCopyrightText: 2020-2024 Dirk Meyer
# SPDX-License-Identifier: Ruby
#
# Parse IMAP accounts for DMARC reports and save them to files
# Input: IMAP folder
# Output: defined in the rulesets
#

# inspired by
# http://wonko.com/post/ruby_script_to_sync_email_from_any_imap_server_to_gmail

# dependecies:
# gem install --user-install new_rfc_2047

require 'openssl'
require 'net/imap'
require 'yaml'
require 'date'
# require 'rfc_2047'

# Maximum number of messages to select at once.
UID_BLOCK_SIZE = 1024
# Lockfile filename
LOCKFILENAME = '/tmp/dmarc-imap.lck'.freeze
# Lockfile timeout
LOCKTIMEOUT = 60 * 60 # 60 min

# https://stackoverflow.com/questions/7488875/how-to-decode-an-rfc-2047-encoded-email-header-in-ruby
# see also: https://github.com/ConradIrwin/rfc2047-ruby/
# see also: https://github.com/tonytonyjan/rfc_2047/
module Rfc2047
  TOKEN = /[\041\043-\047\052\053\055\060-\071\101-\132\134\136\137\141-\176]+/.freeze
  ENCODED_TEXT = /[\041-\076\100-\176]+/.freeze
  ENCODED_WORD = /=\?(?<charset>#{TOKEN})\?(?<encoding>[QqBb])\?(?<encoded_text>#{ENCODED_TEXT})\?=/i.freeze

  class << self
    # encode text
    def encode( input )
      "=?#{input.encoding}?B?#{[ input ].pack( 'm0' )}?="
    end

    # decode text
    def decode( input )
      match_data = ENCODED_WORD.match( input )
      # raise ArgumentError if match_data.nil?
      # not encoded
      return input if match_data.nil?

      charset, encoding, encoded_text = match_data.captures
      decoded =
        case encoding
        when 'Q', 'q' then encoded_text.unpack1( 'M' )
        when 'B', 'b' then encoded_text.unpack1( 'm' )
        end
      decoded.force_encoding( charset )
      begin
        return decoded.encode( 'utf-8' )
      rescue Encoding::InvalidByteSequenceError
        decoded.force_encoding( 'BINARY' )
        warn "InvalidByteSequenceError in #{decoded}"
      end
      decoded
    end
  end
end

# fetch a block of mails
def uid_fetch_block( server, uids, *args, &block )
  pos = 0
  while pos < uids.size
    server.uid_fetch( uids[ pos, UID_BLOCK_SIZE ], *args ).each( &block )
    pos += UID_BLOCK_SIZE
  end
end

# report bad headers
def debug_headers( data )
  puts 'Error in Header:'
  puts data.inspect
end

# decode a header to UTF-8
def save_decode( key, text )
  return nil if text.nil?

  begin
    text = Rfc2047.decode( text )
  rescue Encoding::CompatibilityError => e
    warn "Encoding::CompatibilityError #{e}"
    warn "in #{key}: #{text}"
  rescue StandardError => e
    warn e
    warn "in #{key}: #{text}"
  end
  text
end

# decode all headers to UTF-8
def decode_header( headers )
  headers.each_pair do |key, list|
    list.map! { |text| save_decode( key, text ) }
  end
  headers
end

# fetch all headers of a mail
def fetch_header( data )
  headers = {}
  last = nil
  index = nil
  return headers if data.attr[ 'RFC822.HEADER' ].nil?

  data.attr[ 'RFC822.HEADER' ].split( "\r\n" ).each do |line|
    # p line
    case line
    when /^[ \t]/ # continuation line
      if last.nil? || index.nil?
        debug_headers( line )
        return headers
      end
      headers[ last ][ index ] << line
      next
    end

    # new header line
    key, val = line.split( ':', 2 )
    if val.nil?
      debug_headers( line )
      return headers
    end
    val.strip!
    if headers.key?( key )
      headers[ key ].push( val )
    else
      headers[ key ] = [ val ]
    end
    last = key
    index = headers[ key ].size - 1
  end
  decode_header( headers )
end

# fetch body of a mail
def fetch_body( imap, data )
  key = data.attr[ 'UID' ]
  body = data.attr[ 'RFC822.HEADER' ]
  # pp key
  body << imap.uid_fetch( key, 'BODY[TEXT]' )[ 0 ].attr[ 'BODY[TEXT]' ]
  # pp body
  body
end

# find a header matching the given ruleset
def find_header( rule, headers, key, header )
  unless rule.key?( key )
    return nil # no rule
  end
  unless headers.key?( header )
    # puts "no header '#{header}'"
    return false # no header
  end

  headers[ header ].each do |line|
    if line.include?( rule[ key ] )
      puts "# found: #{rule[ key ]}"
      return true
    end
  end
  # puts "no match '#{header}'"
  false # no match
end

# select and create a IMAP folder
def create_folder( dest, dest_folder )
  puts "Selecting folder '#{dest_folder}'..."
  dest.select( dest_folder )
rescue Net::IMAP::NoResponseError => e
  begin
    warn 'Folder not found; creating...'
    dest.create( dest_folder )
    dest.subscribe( dest_folder )
    dest.select( dest_folder )
  rescue Net::IMAP::NoResponseError => ee
    warn ee.inspect
    @cancel = true
    nil
  rescue StandardError => ee
    warn "Error: could not create folder: #{e}: #{ee}"
    exit 1
  end
end

# strip zone from date line
def clean_date( date )
  date.sub( / \([A-Z]+\)$/, '' )
end

# save mail as file and enumerate in case of duplicates
def run_save( dir, file, body )
  dest = "#{dir}/#{file}"
  unless File.exist?( dest )
    File.write( dest, body )
    return true
  end
  puts "Warning: file exist: #{dest}"
  old = File.read( dest )
  return true if old == body

  2.upto( 5 ) do |i|
    dest = "#{dir}/#{file}.#{i}"
    unless File.exist?( dest )
      File.write( dest, body )
      return true
    end
  end

  false
end

# use IMAP path syntax
def map_target( target )
  return target unless @translate_slash

  target.gsub( '/', '.' )
end

# move mail into target folder
def move_target( imap, imap_uid, target )
  target = map_target( target )
  create_folder( imap, target ) if @create_folder
  puts "# move: #{target}"
  imap.uid_copy( imap_uid, target )
  imap.uid_store( imap_uid, '+FLAGS', [ :Deleted ] )
end

# strip filename from unwanted characters
def clean_filename( filename )
  filename.gsub( /[^[:print:]]/, '_' ).sub( '/', '_' )
end

# execute ruleset on given mail
def run_action( imap, rule, imap_uid, headers, data )
  if rule.key?( 'move' )
    move_target( imap, imap_uid, rule[ 'move' ] )
    return
  end
  return unless rule.key?( 'save' )

  dir = rule[ 'save' ][ 'dir' ]
  unless headers.key?( 'Date' )
    warn 'Error: no Date-Header'
    return
  end
  unless headers.key?( 'Subject' )
    warn 'Error: no Subject-Header'
    return
  end
  puts "# save: #{dir}"
  pp headers[ 'Date' ].first
  pp clean_date( headers[ 'Date' ].first )
  file = Date.rfc2822( clean_date( headers[ 'Date' ].first ) ).to_s
  file << ' '
  file << headers[ 'Subject' ].first
  body = fetch_body( imap, data )
  return unless run_save( dir, clean_filename( file ), body )

  move_target( imap, imap_uid, rule[ 'save' ][ 'move' ] )
end

# check all rulesets of given mail
def run_rules( imap, rules, headers, data )
  moved = false
  rules.each do |rule|
    [ 'from', 'to', 'subject' ].each do |key|
      header = key.capitalize
      next unless find_header( rule, headers, key, header )

      run_action( imap, rule, data.attr[ 'UID' ], headers, data )
      moved = true
      break
    end
    break if moved

    next unless rule.key?( 'match' )
    next unless headers.key?( rule[ 'header' ] )

    headers[ rule[ 'header' ] ].each do |line|
      next unless line.include?( rule[ 'match' ] )

      puts "# found: #{rule[ 'match' ]}"
      run_action( imap, rule, data.attr[ 'UID' ], headers, data )
      moved = true
      break
    end
    break if moved
  end
end

# check input folder for mails
def run_folder( imap, folder, filename )
  rules = YAML.load_file( filename )
  # puts rules.inspect

  begin
    imap.select( folder )
  rescue Net::IMAP::NoResponseError => e
    warn e.inspect
    warn "Folder '#{folder}' not found; abort..."
    return
  end

  suids = imap.uid_search( [ 'ALL' ] )
  puts "folder = '#{folder}' messages = #{suids.length}"
  return unless suids.length.positive?

  uid_fetch_block( imap, suids, [ 'RFC822.HEADER' ] ) do |data|
    break if @cancel

    headers = fetch_header( data )
    if @debug
      pp headers
      puts headers[ 'Subject' ].first if headers.key?( 'Subject' )
      puts
    end
    run_rules( imap, rules, headers, data )
  end
end

# connect to IMAP server and parse mails
def run_sort( config )
  imap = Net::IMAP.new( config[ 'host' ], { port: config[ 'port' ], ssl: { ca_file: config[ 'ca_file' ] } } )
  imap.login( config[ 'login' ], config[ 'password' ] )

  run_folder( imap, config[ 'folder' ], config[ 'rules' ] )

  imap.expunge
  imap.logout
  imap.disconnect
end

# set options from configfile
def parse_options( config )
  @translate_slash = config[ 'translate_slash' ]
  @translate_slash = false if @translate_slash.nil?
  @create_folder = config[ 'create_folder' ]
  @create_folder = false if @create_folder.nil?
end

# parse arguments from commandline
def parse_arguments
  @pattern = nil
  @check_force = false
  @debug = false
  ARGV.each do |arg|
    case arg
    when 'force'
      @check_force = true
    when 'debug'
      @debug = true
    else
      @pattern = argv
    end
  end
end

parse_arguments

# use a lockfile to limit parallel jobs
if File.exist?( LOCKFILENAME )
  puts "locked: #{LOCKFILENAME}"
  unless @check_force
    mtime = File.stat( LOCKFILENAME ).mtime
    exit 0 if mtime.to_i > Time.now.to_i - LOCKTIMEOUT
  end

  warn "unlocking: #{LOCKFILENAME}"
  File.unlink( LOCKFILENAME )
end

File.write( LOCKFILENAME, Time.now.to_s )

# run on each given IMAP account
@cancel = false
dir = 'config'
Dir.foreach( dir ) do |file|
  case file
  when '.', '..'
    next # skip unix entries
  when /[.]yml$/
    puts file
    next if !@pattern.nil? && !/^#{@pattern}/.match( file )

    config = YAML.load_file( "#{dir}/#{file}" )
    parse_options( config )

    # puts config.inspect
    if config.key?( 'disable' )
      puts 'disabled'
      next
    end

    run_sort( config )
  end
end

File.unlink( LOCKFILENAME )

exit 0
# eof
