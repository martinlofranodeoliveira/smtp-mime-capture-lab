module CaptureLab
  class Session
    def initialize(socket, mailbox, fault: nil)
      @socket = socket
      @mailbox = mailbox
      @fault = fault
      @wire = Wire.new(socket, CaptureLab.now + Limits::SESSION_SECONDS)
      @greeted = false
      reset
    end

    def reset
      @sender = nil
      @recipients = []
      @transaction_deadline = nil
    end

    def reply(code, text)
      @wire.write("#{code} #{text}\r\n", @transaction_deadline)
    end

    def run
      reply(220, 'capture-lab example.test')
      commands = 0
      loop do
        line = @wire.read_line(Limits::COMMAND_LINE, @transaction_deadline)
        commands += 1
        raise Error.new('command_limit', 421) if commands > Limits::COMMANDS
        match = /\A([A-Za-z]+)(?: ([ -~]*))?\r\n\z/.match(line)
        unless match
          reply(500, 'command_syntax')
          next
        end
        command = match[1].upcase
        argument = match[2]
        case command
        when 'EHLO', 'HELO'
          if argument && /\A[A-Za-z0-9.-]{1,255}\z/.match?(argument)
            reset
            @greeted = true
            if command == 'EHLO'
              @wire.write("250-capture-lab\r\n250 SIZE #{Limits::RAW}\r\n")
            else
              reply(250, 'hello')
            end
          else
            reply(501, 'greeting_syntax')
          end
        when 'MAIL'
          mail(argument)
        when 'RCPT'
          recipient(argument)
        when 'DATA'
          if argument
            reply(501, 'no_arguments')
          elsif @sender.nil? || @recipients.empty?
            reply(503, 'sender_and_recipient_required')
          else
            receive_data
          end
        when 'RSET'
          if argument
            reply(501, 'no_arguments')
          else
            reset
            reply(250, 'reset')
          end
        when 'NOOP'
          argument ? reply(501, 'no_arguments') : reply(250, 'ok')
        when 'QUIT'
          if argument
            reply(501, 'no_arguments')
          else
            reply(221, 'bye')
            break
          end
        else
          reply(502, 'unsupported')
        end
      end
    rescue EOFError, IOError, SystemCallError
      nil
    rescue Error => error
      begin
        @wire.write("#{error.smtp} #{error.code}\r\n")
      rescue Error, IOError, SystemCallError
        nil
      end
    ensure
      @stage&.abort
      @socket.close unless @socket.closed?
    end

    def mail(argument)
      return reply(503, 'greeting_required') unless @greeted
      match = /\AFROM:<([^<>]*)>(?: SIZE=([0-9]{1,10}))?\z/i.match(argument.to_s)
      return reply(501, 'sender_syntax') unless match && Envelope.sender?(match[1])
      return reply(552, 'declared_size') if match[2] && match[2].to_i > Limits::RAW
      reset
      @sender = match[1]
      @transaction_deadline = CaptureLab.now + Limits::TRANSACTION_SECONDS
      reply(250, 'sender_ok')
    end

    def recipient(argument)
      return reply(503, 'sender_required') if @sender.nil?
      match = /\ATO:<([^<>]+)>\z/i.match(argument.to_s)
      return reply(501, 'recipient_syntax') unless match && Envelope.address?(match[1])
      return reply(550, 'example.test_only') unless Envelope.recipient?(match[1])
      return reply(452, 'recipient_limit') if @recipients.length >= Limits::RECIPIENTS
      @recipients << match[1]
      reply(250, 'recipient_ok')
    end

    def receive_data
      begin
        @stage = @mailbox.begin_stage(@sender, @recipients)
      rescue Error => error
        reset
        reply(error.smtp, error.code)
        return
      end
      reply(354, 'end_with_dot')
      wire_bytes = 0
      headers = HeaderBudget.new
      loop do
        line = @wire.read_line(Limits::DATA_LINE, @transaction_deadline, data: true)
        wire_bytes += line.bytesize
        raise Error.new('data_wire_limit', 552) if wire_bytes > Limits::DATA_WIRE
        break if line == ".\r\n"
        line = line.byteslice(1..) if line.start_with?('.')
        raise Error.new('wire_encoding', 554) unless line.ascii_only? && !line.include?("\0")
        headers.add(line)
        @stage.write(line)
      end
      headers.finish
      raise Error.new('deadline', 421) if CaptureLab.now >= @transaction_deadline
      id = @stage.commit(fault: @fault)
      @stage = nil
      reset
      reply(250, "stored #{id}")
    end
  end
end
