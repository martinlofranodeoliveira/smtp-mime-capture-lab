module CaptureLab
  module Fixture
    SENDER = 'fixture@example.test'
    RECIPIENTS = %w[alice@example.test bob@example.test].freeze
    TEXT = "Olá\n.linha\n".freeze
    RAW = [
      'From: fixture@example.test',
      'To: alice@example.test, bob@example.test',
      'Date: Thu, 01 Jan 2026 00:00:00 +0000',
      'Message-ID: <fixture-001@example.test>',
      'Subject: Synthetic capture',
      'MIME-Version: 1.0',
      'Content-Type: multipart/mixed; boundary="lab-fixed-001"',
      '',
      '--lab-fixed-001',
      'Content-Type: text/plain; charset=UTF-8',
      'Content-Transfer-Encoding: quoted-printable',
      '',
      'Ol=C3=A1',
      '.linha',
      '',
      '--lab-fixed-001',
      'Content-Type: application/octet-stream',
      'Content-Disposition: attachment; filename="sample.bin"',
      'Content-Transfer-Encoding: base64',
      '',
      'AAECAw==',
      '--lab-fixed-001--',
      ''
    ].join("\r\n").b.freeze
  end
end
