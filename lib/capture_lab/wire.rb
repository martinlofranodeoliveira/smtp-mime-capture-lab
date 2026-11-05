module CaptureLab
  class HeaderBudget
    attr_reader :done

    def initialize
      @done = false
      @count = 0
      @total = 0
      @field = 0
    end

    def add(line)
      return if @done
      if line == "\r\n"
        @done = true
        return
      end
      @total += line.bytesize
      if line.start_with?(' ', "\t")
        raise Error.new('header_continuation', 554) if @count.zero?
        @field += line.bytesize
      else
        raise Error.new('header_syntax', 554) unless /\A[!-9;-~]+:/.match?(line)
        @count += 1
        @field = line.bytesize
      end
      if @count > Limits::HEADER_FIELDS || @field > Limits::HEADER_FIELD || @total > Limits::HEADERS
        raise Error.new('header_limit', 552)
      end
    end

    def finish
      raise Error.new('header_separator', 554) unless @done
    end
  end

  class Wire
    def initialize(socket, deadline)
      @socket = socket
      @deadline = deadline
      @buffer = ''.b
      @received = 0
    end

    def read_line(limit, transaction_deadline = nil, data: false)
      absolute = [@deadline, transaction_deadline].compact.min
      idle = CaptureLab.now + Limits::IDLE_SECONDS
      loop do
        if (end_at = @buffer.index("\n"))
          line = @buffer.slice!(0, end_at + 1)
          if line.bytesize > limit
            raise Error.new('crlf_required', 500) if line.byteslice(0, limit - 1).include?("\r")
            raise Error.new('line_limit', data ? 552 : 500)
          end
          valid = line.end_with?("\r\n") && !line.byteslice(0, line.bytesize - 2).match?(/[\r\n]/)
          raise Error.new('crlf_required', 500) unless valid
          return line
        end
        if @buffer.bytesize >= limit
          raise Error.new('crlf_required', 500) if @buffer.byteslice(0, limit - 1).include?("\r")
          raise Error.new('line_limit', data ? 552 : 500)
        end
        remaining = [absolute, idle].min - CaptureLab.now
        raise Error.new('deadline', 421) if remaining <= 0
        raise Error.new('deadline', 421) unless IO.select([@socket], nil, nil, remaining)
        chunk = @socket.read_nonblock([4096, limit + 1 - @buffer.bytesize].min, exception: false)
        next if chunk == :wait_readable
        raise EOFError if chunk.nil?
        @received += chunk.bytesize
        raise Error.new('session_wire_limit', 552) if @received > Limits::SESSION_WIRE
        @buffer << chunk
        idle = CaptureLab.now + Limits::IDLE_SECONDS
      end
    end

    def write(text, transaction_deadline = nil)
      deadline = [@deadline, transaction_deadline].compact.min
      offset = 0
      while offset < text.bytesize
        remaining = deadline - CaptureLab.now
        raise Error.new('deadline', 421) if remaining <= 0
        raise Error.new('deadline', 421) unless IO.select(nil, [@socket], nil, remaining)
        count = @socket.write_nonblock(text.byteslice(offset..), exception: false)
        next if count == :wait_writable
        offset += count
      end
    end
  end
end
