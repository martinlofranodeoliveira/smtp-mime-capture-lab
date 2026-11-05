require 'optparse'
require 'net/smtp'
require_relative '../lib/capture_lab'
require_relative '../lib/capture_lab/fixture'

port = nil
begin
  OptionParser.new { |p| p.on('--port NUMBER', Integer) { |value| port = value } }.parse!
  raise CaptureLab::Error, 'port' unless ARGV.empty? && port && port.between?(1, 65_535)
  smtp = Net::SMTP.new('127.0.0.1', port)
  smtp.open_timeout = 2
  smtp.read_timeout = 2
  smtp.disable_starttls
  smtp.start('fixture.example.test') do |client|
    client.send_message(CaptureLab::Fixture::RAW, CaptureLab::Fixture::SENDER, CaptureLab::Fixture::RECIPIENTS)
  end
  puts JSON.generate('sent' => true)
rescue StandardError
  warn JSON.generate('sent' => false, 'error' => 'fixture_send_failed')
  exit 1
end
