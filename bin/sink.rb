require 'optparse'
require_relative '../lib/capture_lab'

options = { port: 0 }
parser = OptionParser.new do |p|
  p.banner = 'Usage: bundle exec ruby bin/sink.rb --mailbox PATH [--port 2525]'
  p.on('--mailbox PATH') { |value| options[:root] = value }
  p.on('--port NUMBER', Integer) { |value| options[:port] = value }
  p.on('--fault PHASE', %w[before-publish after-publish]) { |value| options[:fault] = value }
end
begin
  parser.parse!
  raise CaptureLab::Error, 'arguments' unless ARGV.empty? && options[:root]
  server = CaptureLab::Server.new(**options)
  Signal.trap('TERM') { server.stop }
  Signal.trap('INT') { server.stop }
  server.run
rescue CaptureLab::Error, OptionParser::ParseError, SystemCallError, IOError => error
  code = error.is_a?(CaptureLab::Error) ? error.code : 'sink_failure'
  warn JSON.generate('ok' => false, 'error' => code)
  exit 1
end
