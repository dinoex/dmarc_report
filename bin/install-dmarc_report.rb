#!/usr/bin/env ruby

# = install-dmarc_report.rb
#
# Author::    Dirk Meyer
# Copyright:: Copyright (c) 2023 Dirk Meyer
# License::   Distributes under the same terms as Ruby
# SPDX-FileCopyrightText: 2023 Dirk Meyer
# SPDX-License-Identifier: Ruby
#
# Installs a working directory for DMARC reports
#

require 'fileutils'

bindir = File.dirname( File.expand_path( __FILE__ ) )
user_dir = Gem.user_dir

def install_sample( src, dest )
  return unless File.exist?( src )

  if File.exist?( dest )
    warn "skipped: #{dest}"
    return
  end

  FileUtils.copy_file( src, dest, verbose: true )
end

[ 'config', 'rules' ].each do |dir|
  FileUtils.mkdir_p( dir )
end

[ 'examples', "#{user_dir}/gems/dmarc_report-*/examples" ].each do |dir|
  list = Dir.glob( dir )
  next if list.empty?

  dir2 = list.last
  [ 'config/*', 'rules/*', '*' ].each do |dir3|
    list3 = Dir.glob( "#{dir2}/#{dir3}" )
    list3.each do |file|
      next unless File.exist?( file )
      next if File.directory?( file )

      target = file.sub( /^.*\/examples\//, '' )
      install_sample( file, target )
    end
  end
end

[ '.', "#{user_dir}/gems/dmarc_report-*" ].each do |dir|
  list = Dir.glob( dir )
  next if list.empty?

  dir2 = list.last
  [ 'README.md', '' ].each do |dir3|
    list3 = Dir.glob( "#{dir2}/#{dir3}" )
    list3.each do |file|
      next unless File.exist?( file )
      next if File.directory?( file )

      target = file.sub( /^.*\//, '' )
      install_sample( file, target )
    end
  end
end

Dir.glob( 'config/*.yml' ).each do |file|
  File.chmod( 0o600, file )
end

datadir = File.expand_path( '.' )

run = "#!/bin/sh
# SPDX-FileCopyrightText: 2023 Dirk Meyer
# SPDX-License-Identifier: Ruby

bindir=\"#{bindir}\"
datadir=\"#{datadir}\"
cd \"${datadir}\" || exit 69

PATH=\"${PATH}:#{bindir}\"
export PATH

mkdir -p log DMARC/in DMARC/seen DMARC/ripmime DMARC/zips DMARC/xml DMARC/old
\"${bindir}/dmarc_imap.rb\" > log/dmarc_imap.log
\"${bindir}/dmarc_ripmime.rb\" > log/dmarc_ripmime.log
\"${bindir}/dmarc_report.rb\" > log/dmarc_report.log
\"${bindir}/dmarc_dns.rb\"

# get config
. ./dmarc-profile.sh

if test \"${EXPIRE_DAYS}\" != \"\"
then
	find DMARC/xml -name '*.xml' -and -mtime \"+${EXPIRE_DAYS}\" \
		-exec mv '{}' 'DMARC/old/' ';'
fi

if test \"${RSYNC_TARGET}\" != \"\"
then
	rsync -a dmarc-report.csv dmarc-dns.json \"${RSYNC_TARGET}\"
fi
exit 0
# eof
"

File.write( 'run-dmarc.sh', run )
File.chmod( 0o755, 'run-dmarc.sh' )
puts 'writing run-dmarc.sh'

crontab = `crontab -l`
unless crontab.include?( 'dmarc' )
  crontab << \
    "# crontab for dmarc_report\n" \
    "#minute\thour\tmday\tmonth\twday\tcommand\n" \
    "#13\t8,12,18\t*\t*\t*\t#{datadir}/run-dmarc.sh\n" \
    "#\n"
  File.write( 'crontab.new', crontab )
  system( 'crontab crontab.new' )
  puts 'writing crontab'
end

exit 0
#
# eof
