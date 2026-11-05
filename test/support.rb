require 'fileutils'
require 'digest'
require_relative '../lib/capture_lab/scenario'

module TestSupport
  def with_lab(start: true, fault: nil)
    lab = CaptureLab::Scenario.new
    lab.start(fault: fault) if start
    yield lab
  ensure
    lab&.close
  end

  def entries(lab)
    CaptureLab::MailboxReader.new(lab.root).list
  end

  def fresh_delivery(lab)
    lab.send_fixture
    assert entries(lab).any?
  end

  def plain(body = "hello\r\n")
    "From: fixture@example.test\r\nContent-Type: text/plain; charset=us-ascii\r\n\r\n#{body}"
  end

  def inspect_raw(raw)
    CaptureLab::Inspector.raw(raw.b)
  end

  def multipart(parts, boundary: 'independent-boundary')
    "MIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary=\"#{boundary}\"\r\n\r\n" +
      parts.map { |part| "--#{boundary}\r\n#{part}\r\n" }.join + "--#{boundary}--\r\n"
  end

  def binary_part(encoded, name)
    "Content-Type: application/octet-stream\r\nContent-Disposition: attachment; filename=\"#{name}\"\r\nContent-Transfer-Encoding: base64\r\n\r\n#{encoded}"
  end

  class Client
    def initialize(port)
      @socket = TCPSocket.new('127.0.0.1', port)
      @buffer = ''.b
      @deadline = CaptureLab.now + 6.0
      @greeting = response
    end

    attr_reader :greeting

    def write(bytes)
      offset = 0
      while offset < bytes.bytesize
        remaining = @deadline - CaptureLab.now
        raise 'client write deadline' if remaining <= 0 || !IO.select(nil, [@socket], nil, remaining)
        count = @socket.write_nonblock(bytes.byteslice(offset, 4096), exception: false)
        offset += count unless count == :wait_writable
      end
    end

    def line
      loop do
        if (index = @buffer.index("\n"))
          return @buffer.slice!(0, index + 1)
        end
        remaining = @deadline - CaptureLab.now
        raise 'client read deadline' if remaining <= 0 || !IO.select([@socket], nil, nil, remaining)
        chunk = @socket.read_nonblock(4096, exception: false)
        next if chunk == :wait_readable
        return nil if chunk.nil?
        @buffer << chunk
        raise 'unbounded server response' if @buffer.bytesize > 8192
      end
    rescue Errno::ECONNRESET
      nil
    end

    def response
      first = line
      return nil unless first
      result = first.dup
      if first[3] == '-'
        loop do
          following = line
          raise 'truncated response' unless following
          result << following
          break if following[3] == ' '
          raise 'unbounded multiline response' if result.bytesize > 8192
        end
      end
      result
    end

    def command(text)
      write("#{text}\r\n")
      response
    end

    def prepare(sender: 'fixture@example.test', recipients: ['alice@example.test'])
      raise 'EHLO failed' unless command('EHLO independent.test').start_with?('250')
      raise 'MAIL failed' unless command("MAIL FROM:<#{sender}>").start_with?('250')
      recipients.each do |recipient|
        raise 'RCPT failed' unless command("RCPT TO:<#{recipient}>").start_with?('250')
      end
    end

    def deliver(raw)
      raise 'DATA failed' unless command('DATA').start_with?('354')
      # Independent wire implementation, not the sink's line reader.
      raw.each_line("\r\n") { |line| write((line.start_with?('.') ? '.' : '') + line) }
      write(".\r\n")
      response
    end

    def close
      @socket.close unless @socket.closed?
    end
  end
end

class LabTest < Minitest::Test
  include TestSupport
end
