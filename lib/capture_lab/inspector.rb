module CaptureLab
  class Inspector
    def self.raw(bytes)
      return { 'ok' => false, 'error' => 'wire_encoding' } unless bytes.is_a?(String)
      raw_bytes = bytes.b
      return { 'ok' => false, 'error' => 'raw_limit' } if raw_bytes.bytesize > Limits::RAW
      result = ProcessRunner.run(
        [RbConfig.ruby, File.join(ROOT, 'bin/decode.rb')],
        input: raw_bytes, timeout: Limits::WORKER_SECONDS, constrained: true
      )
      return { 'ok' => false, 'error' => 'worker_failed' } unless result.status.success?
      data = JSON.parse(result.stdout, max_nesting: 16)
      raise Error, 'worker_protocol' unless data.is_a?(Hash) && [true, false].include?(data['ok'])
      data
    rescue Error => error
      { 'ok' => false, 'error' => error.code }
    rescue JSON::ParserError, SystemCallError
      { 'ok' => false, 'error' => 'worker_protocol' }
    end

    def self.delivery(root, id)
      entry = MailboxReader.new(root).read(id)
      raw = entry.delete('raw')
      entry['inspection'] = self.raw(raw)
      entry
    end
  end
end
