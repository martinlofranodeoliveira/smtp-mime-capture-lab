module CaptureLab
  class Server
    def initialize(root:, port: 0, fault: nil, events: $stdout)
      raise Error, 'port' unless port.is_a?(Integer) && port.between?(0, 65_535)
      raise Error, 'fault' unless [nil, 'before-publish', 'after-publish'].include?(fault)
      @mailbox = Mailbox.new(root)
      @listener = TCPServer.new('127.0.0.1', port)
      @listener.listen(Limits::SESSIONS)
      @events = events
      @fault_phase = fault
      @mutex = Mutex.new
      @clients = {}
      @threads = []
      @stopping = false
    rescue StandardError
      @listener&.close
      @mailbox&.close
      raise
    end

    def emit(data)
      @events.puts(JSON.generate(data))
      @events.flush
    end

    def stop
      @stopping = true
    end

    def fault(phase)
      return unless phase == @fault_phase
      emit('event' => 'fault', 'phase' => phase)
      sleep 0.05 until @stopping
      Process.exit!(1)
    end

    def run
      emit('event' => 'ready', 'address' => '127.0.0.1', 'port' => @listener.addr[1])
      until @stopping
        @threads.reject! { |thread| !thread.alive? && thread.join }
        next unless IO.select([@listener], nil, nil, 0.05)
        socket = @listener.accept_nonblock(exception: false)
        next if socket == :wait_readable
        admitted = @mutex.synchronize do
          if @clients.length < Limits::SESSIONS
            @clients[socket] = true
            true
          else
            false
          end
        end
        unless admitted
          socket.write_nonblock("421 session_limit\r\n", exception: false)
          socket.close
          next
        end
        @threads << Thread.new(socket) do |client|
          Thread.current.report_on_exception = false
          begin
            Session.new(client, @mailbox, fault: method(:fault)).run
          rescue StandardError
            client.close unless client.closed?
          ensure
            @mutex.synchronize { @clients.delete(client) }
          end
        end
      end
    ensure
      @listener.close unless @listener.closed?
      @mutex.synchronize { @clients.each_key { |socket| socket.close unless socket.closed? } }
      @threads.each { |thread| thread.join(1) }
      @threads.each { |thread| thread.kill.join if thread.alive? }
      @mailbox.close
    end
  end
end
