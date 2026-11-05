require 'optparse'
require_relative '../lib/capture_lab'

options = { json: false }
parser = OptionParser.new do |p|
  p.banner = 'Usage: bundle exec ruby bin/inspect.rb --mailbox PATH [--id 000001] [--json]'
  p.on('--mailbox PATH') { |value| options[:root] = value }
  p.on('--id ID') { |value| options[:id] = value }
  p.on('--json') { options[:json] = true }
end
begin
  parser.parse!
  raise CaptureLab::Error, 'arguments' unless ARGV.empty? && options[:root]
  if options[:id]
    report = CaptureLab::Inspector.delivery(options[:root], options[:id])
    inspection = report.fetch('inspection')
    if options[:json]
      puts JSON.generate(report)
    else
      puts "delivery: #{report['id']}"
      puts "envelope: #{JSON.generate(report['envelope'])}"
      puts "inspection: #{inspection['ok'] ? 'ok' : inspection['error']}"
      inspection.fetch('texts', []).each { |part| puts "text: #{JSON.generate(part['text'])}" }
      inspection.fetch('attachments', []).each do |part|
        puts "attachment: #{JSON.generate(part['name'])} bytes=#{part['decoded_bytes']} sha256=#{part['sha256']} hex=#{part['hex']}"
      end
    end
    exit(inspection['ok'] ? 0 : 1)
  else
    entries = CaptureLab::MailboxReader.new(options[:root]).list
    if options[:json]
      puts JSON.generate('deliveries' => entries)
    else
      puts "deliveries: #{entries.length}"
      entries.each { |entry| puts "#{entry['id']} bytes=#{entry['raw_bytes']} recipients=#{JSON.generate(entry['envelope']['rcpt_to'])}" }
    end
  end
rescue CaptureLab::Error, OptionParser::ParseError, SystemCallError, IOError => error
  code = error.is_a?(CaptureLab::Error) ? error.code : 'inspect_failure'
  puts JSON.generate('ok' => false, 'error' => code)
  exit 1
end
