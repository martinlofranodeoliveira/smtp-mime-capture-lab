class StorageTest < LabTest
  def with_store
    Dir.mktmpdir('storage-lab-') do |namespace|
      root = File.join(namespace, 'mailbox')
      store = CaptureLab::Mailbox.new(root)
      begin
        yield store, root
      ensure
        store.close
      end
    end
  end

  def test_failed_stage_does_not_allocate_id_and_reader_is_callable
    with_store do |store, root|
      stage = store.begin_stage('', ['alice@example.test'])
      stage.write(plain)
      stage.abort
      assert_empty CaptureLab::MailboxReader.new(root).list
      stage = store.begin_stage('', ['alice@example.test'])
      stage.write(plain)
      assert_equal '000001', stage.commit
      assert_equal plain, CaptureLab::MailboxReader.new(root).read('000001')['raw']
      assert_equal 0o700, File.stat(root).mode & 0o777
      assert_equal 0o600, File.stat(File.join(root, 'delivery-000001/message.eml')).mode & 0o777
      assert_raises(CaptureLab::Error) { CaptureLab::MailboxReader.new(root).read('../other') }
    end
  end

  def test_committed_plus_inflight_message_slots_are_reserved
    with_store do |store, root|
      96.times do
        stage = store.begin_stage('', ['alice@example.test'])
        stage.write(plain)
        stage.commit
      end
      stages = 4.times.map { store.begin_stage('', ['alice@example.test']) }
      error = assert_raises(CaptureLab::Error) { store.begin_stage('', ['alice@example.test']) }
      assert_equal 'mailbox_capacity', error.code
      stages[0].abort
      replacement = store.begin_stage('', ['bob@example.test'])
      (stages.drop(1) + [replacement]).each { |stage| stage.write(plain); stage.commit }
      assert_equal 100, CaptureLab::MailboxReader.new(root).list.length
      assert_equal '000100', CaptureLab::MailboxReader.new(root).list.last['id']
      assert_raises(CaptureLab::Error) { store.begin_stage('', ['alice@example.test']) }
    end
  end

  def test_aggregate_reservation_under_four_concurrent_writers
    with_store do |store, root|
      63.times do
        stage = store.begin_stage('', ['alice@example.test'])
        stage.write('x' * CaptureLab::Limits::RAW)
        stage.commit
      end
      stages = 4.times.map { store.begin_stage('', ['alice@example.test']) }
      outcomes = Queue.new
      threads = stages.map do |stage|
        Thread.new do
          begin
            stage.write('y' * (128 * 1024))
            outcomes << stage.commit
          rescue CaptureLab::Error => error
            outcomes << error.code
          ensure
            stage.abort
          end
        end
      end
      threads.each(&:join)
      results = 4.times.map { outcomes.pop }
      assert_includes results, 'storage_limit'
      assert_operator store.stats['payload_bytes'], :<=, 16 * 1024 * 1024
      assert_equal 0, store.stats['stages']
      ids = CaptureLab::MailboxReader.new(root).list.map { |entry| entry['id'] }
      assert_equal (1..ids.length).map { |id| format('%06d', id) }, ids
      assert_operator ids.length, :<=, 64
    end
  end

  def test_foreign_stage_is_not_deleted
    Dir.mktmpdir('foreign-lab-') do |namespace|
      root = File.join(namespace, 'mailbox')
      store = CaptureLab::Mailbox.new(root)
      store.close
      foreign = File.join(root, "stage-#{'a' * 32}")
      Dir.mkdir(foreign, 0o700)
      File.write(File.join(foreign, 'foreign.txt'), 'synthetic', mode: 'w', perm: 0o600)
      error = assert_raises(CaptureLab::Error) { CaptureLab::Mailbox.new(root) }
      assert_equal 'foreign_stage', error.code
      assert_equal 'synthetic', File.read(File.join(foreign, 'foreign.txt'))
    end
  end

  def test_orphan_cleanup_count_is_bounded_before_deletion
    Dir.mktmpdir('orphan-lab-') do |namespace|
      root = File.join(namespace, 'mailbox')
      store = CaptureLab::Mailbox.new(root)
      store.close
      5.times do |index|
        path = File.join(root, format('stage-%032x', index))
        Dir.mkdir(path, 0o700)
        File.write(File.join(path, '.owned'), CaptureLab::StorePaths::MARKER, mode: 'w', perm: 0o600)
      end
      error = assert_raises(CaptureLab::Error) { CaptureLab::Mailbox.new(root) }
      assert_equal 'orphan_limit', error.code
      assert_equal 5, Dir.children(root).grep(CaptureLab::StorePaths::STAGE).length
    end
  end

  def test_symlink_and_untrusted_metadata_are_rejected
    with_store do |store, root|
      stage = store.begin_stage('', ['alice@example.test'])
      stage.write(plain)
      stage.commit
      path = File.join(root, 'delivery-000001/envelope.json')
      File.write(path, '{"version":1,"mail_from":"","rcpt_to":["bad@outside.invalid"]}')
      error = assert_raises(CaptureLab::Error) { CaptureLab::MailboxReader.new(root).read('000001') }
      assert_equal 'envelope_metadata', error.code
      File.unlink(path)
      File.symlink('message.eml', path)
      assert_raises(CaptureLab::Error) { CaptureLab::MailboxReader.new(root).read('000001') }
    end
  end
end
