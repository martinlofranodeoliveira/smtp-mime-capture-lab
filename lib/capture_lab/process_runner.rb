module CaptureLab
  module ProcessRunner
    Result = Struct.new(:stdout, :stderr, :status, keyword_init: true)

    def self.kill_group(pid, signal)
      Process.kill(signal, -pid)
    rescue Errno::ESRCH
      nil
    end

    def self.options(constrained)
      result = { pgroup: true, close_others: true }
      if constrained
        result[:rlimit_cpu] = [2, 2] if Process.const_defined?(:RLIMIT_CPU)
        result[:rlimit_as] = [384 * 1024 * 1024, 384 * 1024 * 1024] if Process.const_defined?(:RLIMIT_AS)
        result[:rlimit_core] = [0, 0] if Process.const_defined?(:RLIMIT_CORE)
        result[:rlimit_nofile] = [32, 32] if Process.const_defined?(:RLIMIT_NOFILE)
      end
      result
    end

    def self.run(argv, input: ''.b, timeout: 5.0, output_limit: Limits::WORKER_OUTPUT, constrained: false)
      stdin_read, stdin_write = IO.pipe
      stdout_read, stdout_write = IO.pipe
      stderr_read, stderr_write = IO.pipe
      owned = false
      pid = Process.spawn(*argv, **options(constrained), in: stdin_read, out: stdout_write, err: stderr_write)
      owned = true
      [stdin_read, stdout_write, stderr_write].each(&:close)
      outputs = { stdout_read => ''.b, stderr_read => ''.b }
      readers = outputs.keys.dup
      offset = 0
      status = nil
      deadline = CaptureLab.now + timeout
      loop do
        if offset == input.bytesize && !stdin_write.closed?
          stdin_write.close
        end
        # Do not reap the group leader while descendants may still hold an
        # output pipe. Its unreaped PID anchors the owned process-group ID.
        if !status && readers.empty?
          begin
            waited = Process.waitpid2(pid, Process::WNOHANG)
          rescue Errno::ECHILD
            owned = false
            raise Error, 'worker_ownership'
          end
          if waited
            status = waited[1]
            owned = false
          end
        end
        break if status && readers.empty?
        remaining = deadline - CaptureLab.now
        raise Error, 'worker_timeout' if remaining <= 0
        writers = stdin_write.closed? ? [] : [stdin_write]
        poll = readers.empty? && writers.empty? ? 0.002 : 0.05
        ready = IO.select(readers, writers, nil, [remaining, poll].min)
        next unless ready
        ready[0].each do |io|
          bytes = io.read_nonblock(8192, exception: false)
          next if bytes == :wait_readable
          if bytes.nil?
            readers.delete(io)
            io.close
          else
            outputs[io] << bytes
            cap = io == stderr_read ? 16 * 1024 : output_limit
            raise Error, 'worker_output' if outputs[io].bytesize > cap
          end
        end
        ready[1].each do |io|
          begin
            count = io.write_nonblock(input.byteslice(offset, 8192), exception: false)
            offset += count unless count == :wait_writable
          rescue Errno::EPIPE
            io.close
          end
        end
      end
      Result.new(stdout: outputs[stdout_read], stderr: outputs[stderr_read], status: status)
    ensure
      if pid && owned
        # Failure signals always precede our blocking wait. Once collected,
        # the numeric PID/PGID must never again be used as a signal target.
        kill_group(pid, 'KILL')
        begin
          Process.waitpid(pid)
        rescue Errno::ECHILD
          nil
        ensure
          owned = false
        end
      end
      [stdin_read, stdin_write, stdout_read, stdout_write, stderr_read, stderr_write].compact.each do |io|
        io.close unless io.closed?
      end
    end

    class Service
      attr_reader :pid

      def initialize(argv)
        @out, out_write = IO.pipe
        @err, err_write = IO.pipe
        @pid = Process.spawn(*argv, **ProcessRunner.options(false), in: File::NULL, out: out_write, err: err_write)
        out_write.close
        err_write.close
        @buffer = ''.b
        @bytes = 0
        @readers = [@out, @err]
        @stopped = false
      rescue StandardError
        [@out, @err, out_write, err_write].compact.each { |io| io.close unless io.closed? }
        raise
      end

      def event(timeout: 5.0)
        deadline = CaptureLab.now + timeout
        loop do
          if (index = @buffer.index("\n"))
            line = @buffer.slice!(0, index + 1)
            return JSON.parse(line, max_nesting: 8)
          end
          remaining = deadline - CaptureLab.now
          raise Error, 'service_timeout' if remaining <= 0
          raise Error, 'service_closed' if @readers.empty?
          ready = IO.select(@readers, nil, nil, remaining)
          raise Error, 'service_timeout' unless ready
          ready[0].each do |io|
            bytes = io.read_nonblock(4096, exception: false)
            next if bytes == :wait_readable
            if bytes.nil?
              @readers.delete(io)
              io.close
            else
              @bytes += bytes.bytesize
              raise Error, 'service_output' if @bytes > 64 * 1024
              @buffer << bytes if io == @out
            end
          end
        end
      rescue JSON::ParserError
        raise Error, 'service_json'
      end

      def stop(signal = 'TERM')
        return if @stopped
        ProcessRunner.kill_group(@pid, signal)
        deadline = CaptureLab.now + 0.5
        loop do
          result = Process.waitpid(@pid, Process::WNOHANG)
          break if result
          if CaptureLab.now >= deadline
            ProcessRunner.kill_group(@pid, 'KILL')
            Process.waitpid(@pid)
            break
          end
          sleep 0.01
        end
      rescue Errno::ECHILD
        nil
      ensure
        @stopped = true
        [@out, @err].each { |io| io.close unless io.closed? }
      end
    end
  end
end
