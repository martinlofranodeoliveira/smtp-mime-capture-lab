class RecoveryTest < LabTest
  def send_until_gate(lab)
    client = Client.new(lab.port)
    client.prepare
    assert_match(/^354 /, client.command('DATA'))
    CaptureLab::Fixture::RAW.each_line("\r\n") { |line| client.write((line.start_with?('.') ? '.' : '') + line) }
    client.write(".\r\n")
    event = lab.service.event(timeout: lab.remaining)
    assert_equal 'fault', event['event']
    client
  end

  def test_prepublication_crash_removes_only_owned_orphan_and_reuses_uncommitted_id
    with_lab(fault: 'before-publish') do |lab|
      client = send_until_gate(lab)
      assert_equal 1, Dir.children(lab.root).grep(CaptureLab::StorePaths::STAGE).length
      assert_empty entries(lab)
      lab.stop('TERM')
      assert_equal 1, Dir.children(lab.root).grep(CaptureLab::StorePaths::STAGE).length
      lab.start
      assert_empty entries(lab)
      assert_empty Dir.children(lab.root).grep(CaptureLab::StorePaths::STAGE)
      lab.send_fixture
      assert_equal ['000001'], entries(lab).map { |entry| entry['id'] }
    ensure
      client&.close
    end
  end

  def test_postpublication_crash_and_lost_250_retry_produces_duplicate
    with_lab(fault: 'after-publish') do |lab|
      client = send_until_gate(lab)
      assert_equal ['000001'], entries(lab).map { |entry| entry['id'] }
      lab.stop('KILL')
      # No final 250 was returned, but the complete directory was published.
      assert_nil client.response
      lab.start
      assert_equal ['000001'], entries(lab).map { |entry| entry['id'] }
      lab.send_fixture
      assert_equal %w[000001 000002], entries(lab).map { |entry| entry['id'] }
      reader = CaptureLab::MailboxReader.new(lab.root)
      assert_equal reader.read('000001')['raw'], reader.read('000002')['raw']
    ensure
      client&.close
    end
  end

  def test_second_sink_cannot_take_lifetime_mailbox_ownership
    with_lab do |lab|
      result = CaptureLab::ProcessRunner.run([
        RbConfig.ruby, File.join(CaptureLab::ROOT, 'bin/sink.rb'), '--mailbox', lab.root
      ])
      refute result.status.success?
      assert_equal 'mailbox_owned', JSON.parse(result.stderr)['error']
      fresh_delivery(lab)
    end
  end
end
