require 'tmpdir'
require_relative '../capture_lab'
require_relative 'fixture'

module CaptureLab
  class Scenario
    attr_reader :root, :port, :service

    def initialize
      @namespace = Dir.mktmpdir('smtp-mime-lab-')
      @root = File.join(@namespace, 'mailbox')
      @deadline = CaptureLab.now + 20.0
    end

    def remaining(cap = 5.0)
      seconds = [cap, @deadline - CaptureLab.now].min
      raise Error, 'scenario_deadline' if seconds <= 0
      seconds
    end

    def start(fault: nil)
      args = [RbConfig.ruby, File.join(ROOT, 'bin/sink.rb'), '--mailbox', @root, '--port', '0']
      args += ['--fault', fault] if fault
      @service = ProcessRunner::Service.new(args)
      ready = @service.event(timeout: remaining)
      raise Error, 'scenario_ready' unless ready['event'] == 'ready' && ready['address'] == '127.0.0.1'
      @port = ready.fetch('port')
      self
    end

    def stop(signal = 'TERM')
      @service&.stop(signal)
      @service = nil
    end

    def send_fixture
      result = ProcessRunner.run(
        [RbConfig.ruby, File.join(ROOT, 'bin/send_fixture.rb'), '--port', @port.to_s], timeout: remaining
      )
      raise Error, 'scenario_sender' unless result.status.success? && JSON.parse(result.stdout)['sent']
    end

    def inspect_delivery(id)
      result = ProcessRunner.run(
        [RbConfig.ruby, File.join(ROOT, 'bin/inspect.rb'), '--mailbox', @root, '--id', id, '--json'],
        timeout: remaining
      )
      raise Error, 'scenario_inspector' unless result.status.success?
      JSON.parse(result.stdout)
    end

    def demo
      start
      send_fixture
      entries = MailboxReader.new(@root).list
      raise Error, 'demo_count' unless entries.length == 1
      report = inspect_delivery(entries.first.fetch('id'))
      inspection = report.fetch('inspection')
      attachment = inspection.fetch('attachments')
      unless report['envelope']['rcpt_to'] == Fixture::RECIPIENTS && inspection['ok'] &&
             inspection['texts'].map { |part| part['text'] } == [Fixture::TEXT] &&
             attachment.length == 1 && attachment[0]['decoded_bytes'] == 4 &&
             attachment[0]['hex'] == '00010203' && attachment[0]['name'] == 'sample.bin'
        raise Error, 'demo_content'
      end
      report
    end

    def close
      stop
      # This path is created by this object, never supplied by a caller.
      FileUtils.remove_entry_secure(@namespace) if @namespace && File.directory?(@namespace)
      @namespace = nil
    end
  end
end
