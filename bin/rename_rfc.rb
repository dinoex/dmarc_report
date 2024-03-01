#!/usr/bin/env ruby

# = rename_rfc
#
# Author::    Dirk Meyer
# Copyright:: Copyright (c) 2023 - 2023 Dirk Meyer
# License::   Distributes under the same terms as Ruby
# SPDX-FileCopyrightText: 2023-2023 Dirk Meyer
# SPDX-License-Identifier: Ruby
#
# Rename RFC2047 encoden filenames to UTF-8
#

# dependecies:
# gem install --user-install new_rfc_2047

require 'rfc_2047'

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

dir = 'DMARC/seen'
Dir.entries( dir ).each do |file|
  file2 = save_decode( 'filename', file )
  next  if file2 == file

  puts file
  File.rename( "#{dir}/#{file}", "#{dir}/#{file2}" )
end

exit 0
# eof
