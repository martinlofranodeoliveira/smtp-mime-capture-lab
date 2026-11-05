require_relative '../lib/capture_lab/scenario'

scenario = CaptureLab::Scenario.new
begin
  raise CaptureLab::Error, 'arguments' unless ARGV.empty? || ARGV == ['--json']
  report = scenario.demo
  if ARGV == ['--json']
    puts JSON.generate('version' => CaptureLab::VERSION, 'checks' => 'passed', 'delivery' => report)
  else
    inspection = report.fetch('inspection')
    attachment = inspection.fetch('attachments').first
    puts "SMTP MIME Capture Lab #{CaptureLab::VERSION} (development)"
    puts "delivery: #{report['id']}"
    puts "recipients: #{report['envelope']['rcpt_to'].join(', ')}"
    puts "text: #{JSON.generate(inspection['texts'].first['text'])}"
    puts "attachment: #{attachment['name']} (#{attachment['decoded_bytes']} bytes, hex #{attachment['hex']})"
    puts 'checks: passed'
  end
rescue StandardError => error
  code = error.is_a?(CaptureLab::Error) ? error.code : 'demo_failure'
  warn JSON.generate('ok' => false, 'error' => code)
  exit 1
ensure
  scenario.close
end
