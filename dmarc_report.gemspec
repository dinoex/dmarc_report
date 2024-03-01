# dokuwiki.gemspec
Gem::Specification.new do |s|
  s.name = 'dmarc_report'
  s.version = '1.0'
  s.date = '2023-12-23'
  s.summary = 'fetch and parse DMARC reports'
  s.description = 'Fetch DMARC report mails via IMAP and extract and convert the data to CSV.'
  s.authors = ['Dirk Meyer']
  s.homepage = 'https://rubygems.org/gems/dmarc-report'
  s.licenses = ['MIT']
  s.files = ['lib/xmltohash.rb', '.rubocop.yml', '.gitignore']
  s.files << 'CHANGELOG.md'
  s.files << 'LICENSE.txt'
  s.files << 'README.md'
  s.files << 'examples/dmarc-profile.sh'
  s.files << 'examples/config/dmarc.yml'
  s.files << 'examples/rules/dmarc.yml'
  s.executables << 'dmarc_dns.rb'
  s.executables << 'dmarc_imap.rb'
  s.executables << 'dmarc_ripmime.rb'
  s.executables << 'dmarc_report.rb'
  s.executables << 'rename_rfc.rb'
  s.executables << 'dmarc_dump.rb'
  s.executables << 'install-dmarc_report.rb'
  s.add_runtime_dependency 'new_rfc_2047', ['~> 1.0', '>= 1.0.0']
  s.add_runtime_dependency 'nokogiri', ['~> 1.0', '>= 1.15.0']
end
