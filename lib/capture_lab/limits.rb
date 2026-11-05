module CaptureLab
  module Limits
    SESSIONS = 4
    RECIPIENTS = 16
    RAW = 256 * 1024
    STORAGE = 16 * 1024 * 1024
    MESSAGES = 100
    ENVELOPE = 8192
    COMMAND_LINE = 512
    DATA_LINE = 1000
    DATA_WIRE = RAW * 2 + 3
    SESSION_WIRE = 1024 * 1024
    COMMANDS = 100
    HEADER_FIELDS = 64
    HEADER_FIELD = 4096
    HEADERS = 16 * 1024
    SESSION_SECONDS = 5.0
    TRANSACTION_SECONDS = 2.0
    IDLE_SECONDS = 1.0
    DECODED = 256 * 1024
    MIME_DEPTH = 8
    MIME_PARTS = 64
    NAME = 1024
    WORKER_SECONDS = 3.0
    WORKER_OUTPUT = 2 * 1024 * 1024
  end

  module Envelope
    LOCAL = /\A[A-Za-z0-9_+\-]+(?:\.[A-Za-z0-9_+\-]+)*\z/
    LABEL = /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/

    def self.address?(value)
      return false unless value.is_a?(String) && value.ascii_only? && value.bytesize <= 254
      local, domain, extra = value.split('@', -1)
      return false if extra || !local || !domain || local.bytesize > 64 || !LOCAL.match?(local)
      labels = domain.split('.', -1)
      labels.length >= 2 && labels.all? { |label| LABEL.match?(label) }
    end

    def self.sender?(value)
      value == '' || address?(value)
    end

    def self.recipient?(value)
      address?(value) && value.split('@', 2).last == 'example.test'
    end

    def self.metadata?(data)
      data.is_a?(Hash) && data.keys.sort == %w[mail_from rcpt_to version] &&
        data['version'] == 1 && sender?(data['mail_from']) &&
        data['rcpt_to'].is_a?(Array) && data['rcpt_to'].length.between?(1, Limits::RECIPIENTS) &&
        data['rcpt_to'].all? { |address| recipient?(address) }
    end
  end
end
