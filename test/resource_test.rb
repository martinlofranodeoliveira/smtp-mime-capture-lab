require 'minitest/mock'

class ResourceTest < LabTest
  def assert_fresh_after_failure(lab, client)
    response = client.response
    assert response.nil? || /\A(?:421|452|552) /.match?(response), response.inspect
    assert_nil client.response if response
    assert_empty entries(lab)
    fresh_delivery(lab)
  end

  def test_data_byte_overflow_closes_without_unbounded_drain
    with_lab do |lab|
      client = Client.new(lab.port)
      client.prepare
      assert_match(/^354 /, client.command('DATA'))
      begin
        client.write("Content-Type: text/plain\r\n\r\n")
        300.times { client.write("#{'x' * 998}\r\n") }
      rescue Errno::EPIPE, Errno::ECONNRESET
        nil
      end
      assert_fresh_after_failure(lab, client)
    ensure
      client&.close
    end
  end

  def test_overlong_data_line
    with_lab do |lab|
      client = Client.new(lab.port)
      client.prepare
      client.command('DATA')
      client.write("Content-Type: text/plain\r\n\r\n#{'x' * 1001}")
      assert_fresh_after_failure(lab, client)
    ensure
      client&.close
    end
  end

  def test_missing_terminator_hits_idle_deadline
    with_lab do |lab|
      client = Client.new(lab.port)
      client.prepare
      client.command('DATA')
      client.write(plain)
      assert_fresh_after_failure(lab, client)
    ensure
      client&.close
    end
  end

  def test_slow_trickle_cannot_extend_absolute_transaction_deadline
    with_lab do |lab|
      client = Client.new(lab.port)
      client.prepare
      client.command('DATA')
      client.write("Content-Type: text/plain\r\n\r\n")
      started = CaptureLab.now
      5.times do
        sleep 0.45
        begin
          client.write('x')
        rescue Errno::EPIPE, Errno::ECONNRESET
          break
        end
      end
      assert_fresh_after_failure(lab, client)
      assert_operator CaptureLab.now - started, :<, 4.0
    ensure
      client&.close
    end
  end

  def test_session_admission_limit
    with_lab do |lab|
      clients = 4.times.map { Client.new(lab.port) }
      extra = Client.new(lab.port)
      assert_match(/^421 session_limit/, extra.greeting)
      clients.each { |client| assert_match(/^220 /, client.greeting) }
    ensure
      clients&.each(&:close)
      extra&.close
    end
  end

  def test_four_smtp_sessions_cannot_bypass_near_full_storage
    with_lab(start: false) do |lab|
      store = CaptureLab::Mailbox.new(lab.root)
      begin
        63.times do
          stage = store.begin_stage('', ['alice@example.test'])
          stage.write('x' * (256 * 1024))
          stage.commit
        end
      ensure
        store.close
      end
      lab.start
      clients = 4.times.map do
        client = Client.new(lab.port)
        client.prepare
        assert_match(/^354 /, client.command('DATA'))
        client
      end
      outcomes = Queue.new
      threads = clients.map do |client|
        Thread.new do
          begin
            client.write("Content-Type: text/plain\r\n\r\n")
            150.times { client.write("#{'y' * 898}\r\n") }
            client.write(".\r\n")
            outcomes << client.response
          rescue Errno::EPIPE, Errno::ECONNRESET
            outcomes << nil
          ensure
            client.close
          end
        end
      end
      threads.each(&:join)
      responses = 4.times.map { outcomes.pop }
      assert_operator responses.count { |response| response&.start_with?('250 ') }, :<=, 1
      assert_operator entries(lab).length, :<=, 64
      assert_operator Dir.glob(File.join(lab.root, '*', '*'), File::FNM_DOTMATCH).select { |path| File.file?(path) }.sum { |path| File.size(path) }, :<=, 16 * 1024 * 1024
      ids = entries(lab).map { |entry| entry['id'] }
      assert_equal (1..ids.length).map { |id| format('%06d', id) }, ids
    ensure
      clients&.each(&:close)
    end
  end

  def test_process_group_signals_precede_reaping_for_real_normal_hanging_and_flooding_children
    cases = [
      ['STDOUT.write("ok")', {}, nil],
      ['sleep 30', { timeout: 0.1 }, 'worker_timeout'],
      ['STDOUT.write("x" * 100000)', { output_limit: 100 }, 'worker_output']
    ]
    cases.each do |program, options, expected_error|
      events = []
      late_signals = []
      reaped = {}
      wait_pair = Process.method(:waitpid2)
      wait_pid = Process.method(:waitpid)
      signal_group = CaptureLab::ProcessRunner.method(:kill_group)
      observed_pair = lambda do |*arguments|
        result = wait_pair.call(*arguments)
        if result
          reaped[result[0]] = true
          events << [:reap, result[0]]
        end
        result
      end
      observed_pid = lambda do |*arguments|
        result = wait_pid.call(*arguments)
        if result
          reaped[result] = true
          events << [:reap, result]
        end
        result
      end
      observed_signal = lambda do |pid, signal|
        events << [:signal, pid]
        if reaped[pid]
          # Record the forbidden attempt, but never send a real signal to a
          # group whose leader the supervisor has already collected.
          late_signals << [pid, signal]
        else
          signal_group.call(pid, signal)
        end
      end
      operation = lambda do
        CaptureLab::ProcessRunner.run([RbConfig.ruby, '-e', program], **options)
      end
      Process.stub(:waitpid2, observed_pair) do
        Process.stub(:waitpid, observed_pid) do
          CaptureLab::ProcessRunner.stub(:kill_group, observed_signal) do
            if expected_error
              error = assert_raises(CaptureLab::Error, &operation)
              assert_equal expected_error, error.code
            else
              result = operation.call
              assert result.status.success?
              assert_equal 'ok', result.stdout
            end
          end
        end
      end
      assert_empty late_signals, "No signal may follow reap: #{events.inspect}"
      assert_equal 1, events.count { |event| event[0] == :reap }
      if expected_error
        assert events.any? { |event| event[0] == :signal }, 'Failure cleanup must still signal the owned group'
      end
    end
  end

  def test_owned_worker_timeout_and_output_cap_reap_children
    error = assert_raises(CaptureLab::Error) do
      CaptureLab::ProcessRunner.run([RbConfig.ruby, '-e', 'sleep 30'], timeout: 0.1)
    end
    assert_equal 'worker_timeout', error.code
    error = assert_raises(CaptureLab::Error) do
      CaptureLab::ProcessRunner.run([RbConfig.ruby, '-e', 'STDOUT.write("x" * 100000)'], output_limit: 100)
    end
    assert_equal 'worker_output', error.code
    assert_raises(Errno::ECHILD) { Process.waitpid(-1, Process::WNOHANG) }
  end
end
