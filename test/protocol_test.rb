class ProtocolTest < LabTest
  def test_independent_net_smtp_and_inspector_subprocess_workflow
    with_lab do |lab|
      lab.send_fixture
      assert_equal 1, entries(lab).length
      report = lab.inspect_delivery('000001')
      assert_equal %w[alice@example.test bob@example.test], report['envelope']['rcpt_to']
      assert_equal ["Olá\n.linha\n"], report['inspection']['texts'].map { |part| part['text'] }
      assert_equal ['00010203'], report['inspection']['attachments'].map { |part| part['hex'] }
      raw = CaptureLab::MailboxReader.new(lab.root).read('000001')['raw']
      assert_includes raw, 'Date: Thu, 01 Jan 2026 00:00:00 +0000'
      assert_includes raw, 'Message-ID: <fixture-001@example.test>'
    end
  end

  def test_demo_cli_human_and_json_modes
    human = CaptureLab::ProcessRunner.run([RbConfig.ruby, File.join(CaptureLab::ROOT, 'bin/demo.rb')], timeout: 15.0)
    assert human.status.success?, human.stderr
    human_text = human.stdout.dup.force_encoding(Encoding::UTF_8)
    assert human_text.valid_encoding?, "Human demo must emit valid UTF-8"
    assert_includes human_text, "delivery: 000001\n"
    assert_includes human_text, "recipients: alice@example.test, bob@example.test\n"
    assert_includes human_text, "text: \"Olá\\n.linha\\n\"\n"
    assert_includes human_text, "attachment: sample.bin (4 bytes, hex 00010203)\n"
    assert_includes human_text, "checks: passed\n"

    machine = CaptureLab::ProcessRunner.run([RbConfig.ruby, File.join(CaptureLab::ROOT, 'bin/demo.rb'), '--json'], timeout: 15.0)
    assert machine.status.success?, machine.stderr
    parsed = JSON.parse(machine.stdout)
    assert_equal 'passed', parsed['checks']
    assert_equal '000001', parsed.dig('delivery', 'id')
  end

  def test_raw_dot_transparency_and_rejected_recipient_preserves_accepted_one
    with_lab do |lab|
      client = Client.new(lab.port)
      client.prepare(sender: '')
      assert_match(/^550 /, client.command('RCPT TO:<someone@outside.invalid>'))
      assert_match(/^354 /, client.command('DATA'))
      # Fixed bytes: this line has two dots ON THE WIRE.
      client.write("Content-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\nOl=C3=A1\r\n..linha\r\n.\r\n")
      assert_match(/^250 stored 000001/, client.response)
      item = CaptureLab::MailboxReader.new(lab.root).read('000001')
      assert_equal '', item['envelope']['mail_from']
      assert_equal ['alice@example.test'], item['envelope']['rcpt_to']
      assert_includes item['raw'], "\r\n.linha\r\n"
      refute_includes item['raw'], "\r\n..linha\r\n"
      assert_equal "Olá\n.linha\n", lab.inspect_delivery('000001')['inspection']['texts'][0]['text']
    ensure
      client&.close
    end
  end

  def test_rset_clears_only_transaction_and_next_transaction_works
    with_lab do |lab|
      client = Client.new(lab.port)
      client.prepare
      assert_match(/^250 /, client.command('RSET'))
      assert_match(/^503 /, client.command('DATA'))
      assert_empty entries(lab)
      assert_match(/^250 /, client.command('MAIL FROM:<fixture@example.test>'))
      assert_match(/^250 /, client.command('RCPT TO:<bob@example.test>'))
      assert_match(/^250 stored 000001/, client.deliver(plain))
      assert_equal ['bob@example.test'], entries(lab)[0]['envelope']['rcpt_to']
      assert_match(/^221 /, client.command('QUIT'))
    ensure
      client&.close
    end
  end

  def test_explicit_extension_and_address_subset
    with_lab do |lab|
      client = Client.new(lab.port)
      assert_match(/^503 /, client.command('MAIL FROM:<>'))
      ehlo = client.command('EHLO synthetic.test')
      assert_equal "250-capture-lab\r\n250 SIZE 262144\r\n", ehlo
      assert_match(/^502 /, client.command('AUTH PLAIN'))
      assert_match(/^502 /, client.command('STARTTLS'))
      assert_match(/^501 /, client.command('MAIL FROM:<"quoted"@example.test>'))
      assert_match(/^552 /, client.command('MAIL FROM:<> SIZE=262145'))
      assert_match(/^250 /, client.command('MAIL FROM:<> SIZE=100'))
      # Uppercase domains are outside address syntax, while subdomains are rejected as non-example.test.
      assert_match(/^501 /, client.command('RCPT TO:<alice@EXAMPLE.test>'))
      assert_match(/^550 /, client.command('RCPT TO:<alice@sub.example.test>'))
      16.times { assert_match(/^250 /, client.command('RCPT TO:<Alice@example.test>')) }
      assert_match(/^452 /, client.command('RCPT TO:<bob@example.test>'))
      assert_match(/^250 /, client.command('NOOP'))
      assert_match(/^250 /, client.deliver(plain))
      assert_equal 16, entries(lab)[0]['envelope']['rcpt_to'].length
    ensure
      client&.close
    end
  end

  def test_identical_messages_are_separate_deliveries
    with_lab do |lab|
      2.times { lab.send_fixture }
      assert_equal %w[000001 000002], entries(lab).map { |entry| entry['id'] }
      reader = CaptureLab::MailboxReader.new(lab.root)
      assert_equal reader.read('000001')['raw'], reader.read('000002')['raw']
    end
  end

  def test_helo_and_bad_framing
    with_lab do |lab|
      client = Client.new(lab.port)
      assert_match(/^250 /, client.command('HELO synthetic.test'))
      client.write("NOOP\n")
      assert_match(/^500 crlf_required/, client.response)
      assert_nil client.response
      assert_empty entries(lab)
      fresh_delivery(lab)
    ensure
      client&.close
    end
  end
end
