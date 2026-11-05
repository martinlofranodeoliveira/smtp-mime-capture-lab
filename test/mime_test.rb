require_relative '../lib/capture_lab/mime_decoder'

class MimeTest < LabTest
  def test_two_independent_attachments_and_aggregate_counts
    raw = multipart([binary_part('AQID', 'three.bin'), binary_part('BAUGBwg=', 'five.bin')])
    report = inspect_raw(raw)
    assert_equal true, report['ok'], report.inspect
    expected = [[1, 2, 3], [4, 5, 6, 7, 8]]
    assert_equal [3, 5], report['attachments'].map { |part| part['decoded_bytes'] }
    assert_equal 8, report['attachment_bytes']
    report['attachments'].zip(expected).each do |part, octets|
      bytes = octets.pack('C*')
      assert_equal octets, [part['hex']].pack('H*').bytes
      assert_equal Digest::SHA256.hexdigest(bytes), part['sha256']
    end
    assert_operator report['diagnostics']['mail_body_splits'], :>=, 1
  end

  def test_filename_is_data_not_a_destination
    raw = multipart([binary_part('AAECAw==', '../../not-extracted.bin')])
    report = inspect_raw(raw)
    assert_equal true, report['ok'], report.inspect
    assert_equal '../../not-extracted.bin', report['attachments'][0]['name']
    assert_equal '00010203', report['attachments'][0]['hex']
  end

  def test_no_partial_success_conceals_bad_second_attachment
    valid = inspect_raw(multipart([binary_part('AAE=', 'valid-two.bin')]))
    assert_equal true, valid['ok'], valid.inspect
    assert_equal '0001', valid['attachments'][0]['hex']
    ['!!!!', 'AB==', 'AAF=', 'AA==junk'].each do |invalid|
      raw = multipart([binary_part('AQID', 'good.bin'), binary_part(invalid, 'bad.bin')])
      report = inspect_raw(raw)
      assert_equal false, report['ok'], invalid
      assert_equal 'transfer_encoding', report['error'], invalid
      refute report.key?('attachments')
    end
  end

  def test_unsupported_charset_transfer_encoded_headers_and_nested_messages_are_errors
    cases = {
      "Content-Type: text/plain; charset=koi8-r\r\n\r\nhello\r\n" => 'charset',
      "Content-Type: text/plain\r\nContent-Transfer-Encoding: binary\r\n\r\nhello\r\n" => 'transfer_encoding',
      "Content-Type: text/plain\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\nbad=Q0\r\n" => 'transfer_encoding',
      "Content-Type: message/rfc822\r\n\r\nSubject: nested\r\n\r\nx\r\n" => 'nested_message',
      "Content-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: base64\r\n\r\n/w==\r\n" => 'text_encoding',
      "Subject: =?utf-8?B?YWJj?=\r\nContent-Type: text/plain\r\n\r\nhello\r\n" => 'encoded_header',
      "Content-Type: application/octet-stream\r\nContent-Disposition: attachment; filename*=utf-8''sample.bin\r\n\r\nx\r\n" => 'encoded_header',
      "Content-Type: application/octet-stream\r\nContent-Disposition: attachment; filename*0*=utf-8''sample.bin\r\n\r\nx\r\n" => 'encoded_header',
      "Content-Type: application/octet-stream\r\nContent-Disposition: attachment; filename*0=\"sample.bin\"\r\n\r\nx\r\n" => 'encoded_header'
    }
    cases.each do |raw, expected|
      result = inspect_raw(raw)
      assert_equal false, result['ok']
      assert_equal expected, result['error'], result.inspect
    end
  end

  def test_truncated_multipart_without_closing_boundary_fails_closed
    truncated = "MIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary=\"trunc\"\r\n\r\n" \
                "--trunc\r\n#{binary_part('AQID', 'first.bin')}\r\n" \
                "--trunc\r\n#{binary_part('BAUGBwg=', 'second.bin')}\r\n"
    result = inspect_raw(truncated)
    assert_equal false, result['ok'], result.inspect
    assert_equal 'mime_invalid', result['error']
    refute result.key?('attachments')
  end

  def test_aggregate_decoded_byte_limit_across_parts_fails_closed
    raw = multipart([
      "Content-Type: text/plain; charset=us-ascii\r\n\r\nhello\r\n",
      binary_part('BAUGBwg=', 'five.bin')
    ])
    decoder = CaptureLab::MimeDecoder.new(decoded_limit: 10)
    result = decoder.inspect(raw)
    assert_equal false, result['ok']
    assert_equal 'decoded_limit', result['error']
    refute result.key?('texts')
    refute result.key?('attachments')
  end

  def test_wide_and_deep_expansion_is_isolated_and_fails_without_success_payload
    wide = multipart(65.times.map { "Content-Type: text/plain\r\n\r\nx" })
    deep = "Content-Type: text/plain\r\n\r\nx\r\n"
    12.times { |index| deep = multipart([deep], boundary: "depth-#{index}") }
    [wide, deep].each do |raw|
      started = CaptureLab.now
      result = inspect_raw(raw)
      assert_equal false, result['ok'], result.inspect
      assert_includes %w[mime_parts mime_depth worker_failed worker_timeout], result['error']
      assert_operator CaptureLab.now - started, :<, 4.5
      refute result.key?('texts')
      if result['diagnostics']
        # This counts the actual Mail::Body#split! path, not our stack operations.
        assert_operator result['diagnostics']['mail_body_splits'], :>, 0
        assert_operator result['diagnostics']['visited_parts'], :<=, 64
      end
    end
  end

  def test_folded_quoted_boundary_is_parsed_by_mail
    raw = "MIME-Version: 1.0\r\nContent-Type: multipart/mixed;\r\n boundary=\"folded-fixture\"\r\n\r\n--folded-fixture\r\nContent-Type: text/plain\r\n\r\nhello\r\n\r\n--folded-fixture--\r\n"
    result = inspect_raw(raw)
    assert_equal true, result['ok'], result.inspect
    assert_equal "hello\n", result['texts'][0]['text']
  end

  def test_raw_and_part_header_limits
    raw = plain('x' * (256 * 1024))
    assert_equal 'raw_limit', inspect_raw(raw)['error']
    fields = 65.times.map { |index| "X-#{index}: value\r\n" }.join
    result = inspect_raw(multipart(["#{fields}\r\nx"]))
    assert_equal false, result['ok']
    assert_equal 'header_limit', result['error']
  end
end
