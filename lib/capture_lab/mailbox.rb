module CaptureLab
  module StorePaths
    MARKER = "smtp-mime-capture-lab:0.1.0\n".freeze
    FILES = %w[.owned envelope.json message.eml].freeze
    DELIVERY = /\Adelivery-([0-9]{6})\z/
    STAGE = /\Astage-[0-9a-f]{32}\z/

    def self.directory(path)
      stat = File.lstat(path)
      unless stat.directory? && stat.uid == Process.uid && (stat.mode & 0o7777) == 0o700
        raise Error, 'unsafe_directory'
      end
      stat
    rescue SystemCallError
      raise Error, 'unsafe_directory'
    end

    def self.regular(path, maximum)
      stat = File.lstat(path)
      unless stat.file? && stat.uid == Process.uid && stat.nlink == 1 &&
             (stat.mode & 0o7777) == 0o600 && stat.size <= maximum
        raise Error, 'unsafe_file'
      end
      stat
    rescue SystemCallError
      raise Error, 'unsafe_file'
    end

    def self.entries(path, maximum = Limits::MESSAGES + Limits::SESSIONS + 2)
      names = []
      Dir.each_child(path) do |name|
        raise Error, 'directory_entry_limit' if names.length >= maximum
        names << name
      end
      names
    rescue SystemCallError
      raise Error, 'unsafe_directory'
    end

    def self.open_lock(path, create:)
      flags = File::RDWR | File::NOFOLLOW
      flags |= File::CREAT if create
      file = File.open(path, flags, 0o600)
      stat = regular(path, 0)
      fstat = file.stat
      raise Error, 'unsafe_file' unless fstat.ino == stat.ino && fstat.dev == stat.dev
      file
    rescue SystemCallError
      file&.close
      raise Error, 'unsafe_file'
    rescue StandardError
      file&.close
      raise
    end

    def self.read(path, maximum)
      stat = regular(path, maximum)
      File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
        fstat = file.stat
        raise Error, 'unsafe_file' unless fstat.ino == stat.ino && fstat.dev == stat.dev && fstat.size <= maximum
        data = file.read(maximum + 1) || ''.b
        raise Error, 'unsafe_file' if data.bytesize > maximum
        data
      end
    rescue SystemCallError
      raise Error, 'unsafe_file'
    end

    def self.delivery(root, name, include_raw: false)
      raise Error, 'delivery_id' unless DELIVERY.match?(name)
      path = File.join(root, name)
      directory(path)
      raise Error, 'delivery_files' unless entries(path, 3).sort == FILES.sort
      marker = read(File.join(path, '.owned'), MARKER.bytesize)
      raise Error, 'ownership_marker' unless marker == MARKER
      envelope = JSON.parse(read(File.join(path, 'envelope.json'), Limits::ENVELOPE), max_nesting: 8)
      raise Error, 'envelope_metadata' unless Envelope.metadata?(envelope)
      size = regular(File.join(path, 'message.eml'), Limits::RAW).size
      result = { 'id' => name.delete_prefix('delivery-'), 'envelope' => envelope, 'raw_bytes' => size }
      result['raw'] = read(File.join(path, 'message.eml'), Limits::RAW) if include_raw
      result
    rescue JSON::ParserError
      raise Error, 'envelope_json'
    end

    def self.file_maximum(name)
      case name
      when '.owned' then MARKER.bytesize
      when 'envelope.json' then Limits::ENVELOPE
      else Limits::RAW
      end
    end

    def self.payload_size(path)
      FILES.sum { |name| regular(File.join(path, name), file_maximum(name)).size }
    end

    def self.validate_orphan(path)
      directory(path)
      names = entries(path, 3)
      raise Error, 'foreign_stage' unless names.include?('.owned') && (names - FILES).empty?
      raise Error, 'ownership_marker' unless read(File.join(path, '.owned'), MARKER.bytesize) == MARKER
      names.each { |name| regular(File.join(path, name), file_maximum(name)) }
    end

    def self.remove_stage(path)
      validate_orphan(path)
      entries(path, 3).each { |name| File.unlink(File.join(path, name)) }
      Dir.rmdir(path)
    end
  end

  class MailboxReader
    def initialize(root)
      @root = File.expand_path(root)
      StorePaths.directory(@root)
    end

    def snapshot
      lock = StorePaths.open_lock(File.join(@root, '.mailbox.lock'), create: false)
      lock.flock(File::LOCK_SH)
      names = StorePaths.entries(@root)
      unknown = names.reject { |name| StorePaths::DELIVERY.match?(name) || StorePaths::STAGE.match?(name) || %w[.owner.lock .mailbox.lock].include?(name) }
      raise Error, 'foreign_mailbox_entry' unless unknown.empty?
      deliveries = names.grep(StorePaths::DELIVERY).sort
      raise Error, 'message_limit' if deliveries.length > Limits::MESSAGES
      yield deliveries
    ensure
      lock&.close
    end

    def list
      snapshot { |names| names.map { |name| StorePaths.delivery(@root, name) } }
    end

    def read(id)
      raise Error, 'delivery_id' unless id.is_a?(String) && /\A[0-9]{6}\z/.match?(id)
      snapshot do |names|
        name = "delivery-#{id}"
        raise Error, 'not_found' unless names.include?(name)
        StorePaths.delivery(@root, name, include_raw: true)
      end
    end
  end

  class Mailbox
    attr_reader :root

    def initialize(root)
      @root = File.expand_path(root)
      begin
        Dir.mkdir(@root, 0o700) unless File.exist?(@root) || File.symlink?(@root)
      rescue SystemCallError
        raise Error, 'unsafe_directory'
      end
      StorePaths.directory(@root)
      @owner = StorePaths.open_lock(File.join(@root, '.owner.lock'), create: true)
      raise Error, 'mailbox_owned' unless @owner.flock(File::LOCK_EX | File::LOCK_NB)
      @lock = StorePaths.open_lock(File.join(@root, '.mailbox.lock'), create: true)
      @mutex = Mutex.new
      @stages = []
      synchronized { recover }
    rescue StandardError
      @lock&.close
      @owner&.close
      raise
    end

    def synchronized
      @mutex.synchronize do
        @lock.flock(File::LOCK_EX)
        begin
          yield
        ensure
          @lock.flock(File::LOCK_UN)
        end
      end
    end

    def recover
      names = StorePaths.entries(@root)
      unknown = names.reject { |name| StorePaths::DELIVERY.match?(name) || StorePaths::STAGE.match?(name) || %w[.owner.lock .mailbox.lock].include?(name) }
      raise Error, 'foreign_mailbox_entry' unless unknown.empty?
      committed = names.grep(StorePaths::DELIVERY).sort
      orphans = names.grep(StorePaths::STAGE)
      raise Error, 'orphan_limit' if orphans.length > Limits::SESSIONS
      raise Error, 'message_limit' if committed.length > Limits::MESSAGES
      @total = 0
      committed.each_with_index do |name, index|
        raise Error, 'delivery_sequence' unless name == format('delivery-%06d', index + 1)
        StorePaths.delivery(@root, name)
        @total += StorePaths.payload_size(File.join(@root, name))
      end
      raise Error, 'storage_limit' if @total > Limits::STORAGE
      orphan_bytes = 0
      orphans.each do |name|
        path = File.join(@root, name)
        StorePaths.validate_orphan(path)
        orphan_bytes += StorePaths.entries(path, 3).sum { |file| File.lstat(File.join(path, file)).size }
      end
      raise Error, 'storage_limit' if @total + orphan_bytes > Limits::STORAGE
      orphans.each { |name| StorePaths.remove_stage(File.join(@root, name)) }
      @count = committed.length
      @last = @count
    end

    def begin_stage(sender, recipients)
      metadata = { 'version' => 1, 'mail_from' => sender, 'rcpt_to' => recipients.dup }
      raise Error, 'envelope_metadata' unless Envelope.metadata?(metadata)
      encoded = JSON.generate(metadata)
      raise Error, 'envelope_limit' if encoded.bytesize > Limits::ENVELOPE
      synchronized do
        if @count + @stages.length >= Limits::MESSAGES || @stages.length >= Limits::SESSIONS
          raise Error.new('mailbox_capacity', 452)
        end
        initial = encoded.bytesize + StorePaths::MARKER.bytesize
        raise Error.new('storage_limit', 452) if @total + initial > Limits::STORAGE
        path = File.join(@root, "stage-#{SecureRandom.hex(16)}")
        Dir.mkdir(path, 0o700)
        stage = Stage.new(self, path, initial)
        @total += initial
        @stages << stage
        begin
          stage.create(encoded)
        rescue StandardError
          stage.discard_locked
          raise
        end
        stage
      end
    end

    def append(stage, bytes)
      synchronized do
        raise Error, 'closed_stage' unless @stages.include?(stage)
        raise Error.new('raw_limit', 552) if stage.raw_bytes + bytes.bytesize > Limits::RAW
        raise Error.new('storage_limit', 452) if @total + bytes.bytesize > Limits::STORAGE
        @total += bytes.bytesize
        stage.reserve(bytes.bytesize)
        stage.file.write(bytes)
      end
    end

    def publish(stage, fault)
      synchronized do
        raise Error, 'closed_stage' unless @stages.include?(stage)
        stage.file.flush
        stage.file.fsync
        stage.file.close
        File.open(stage.path, File::RDONLY) { |directory| directory.fsync }
      end
      fault&.call('before-publish')
      id = synchronized do
        raise Error, 'closed_stage' unless @stages.include?(stage)
        next_id = format('%06d', @last + 1)
        destination = File.join(@root, "delivery-#{next_id}")
        raise Error, 'delivery_collision' if File.exist?(destination)
        File.rename(stage.path, destination)
        stage.published = true
        @stages.delete(stage)
        @last += 1
        @count += 1
        File.open(@root, File::RDONLY) { |directory| directory.fsync }
        next_id
      end
      fault&.call('after-publish')
      id
    end

    def discard_locked(stage)
      return unless @stages.include?(stage)
      stage.file&.close unless stage.file&.closed?
      if File.directory?(stage.path)
        StorePaths.entries(stage.path, 3).each do |name|
          raise Error, 'foreign_stage' unless StorePaths::FILES.include?(name)
          StorePaths.regular(File.join(stage.path, name), StorePaths.file_maximum(name))
          File.unlink(File.join(stage.path, name))
        end
        Dir.rmdir(stage.path)
      end
      @total -= stage.reserved
      @stages.delete(stage)
    end

    def abort(stage)
      synchronized { discard_locked(stage) }
    end

    def stats
      synchronized { { 'messages' => @count, 'stages' => @stages.length, 'payload_bytes' => @total } }
    end

    def close
      @stages.dup.each(&:abort)
      @lock.close
      @owner.close
    end

    class Stage
      attr_reader :path, :file, :reserved, :raw_bytes
      attr_accessor :published

      def initialize(mailbox, path, initial)
        @mailbox = mailbox
        @path = path
        @reserved = initial
        @raw_bytes = 0
        @published = false
      end

      def create(metadata)
        { '.owned' => StorePaths::MARKER, 'envelope.json' => metadata }.each do |name, bytes|
          File.open(File.join(@path, name), File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
            file.write(bytes)
            file.flush
            file.fsync
          end
        end
        @file = File.open(File.join(@path, 'message.eml'), File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600)
      end

      def reserve(count)
        @reserved += count
        @raw_bytes += count
      end

      def write(bytes)
        @mailbox.append(self, bytes)
      end

      def commit(fault: nil)
        @mailbox.publish(self, fault)
      end

      def discard_locked
        @mailbox.discard_locked(self)
      end

      def abort
        @mailbox.abort(self) unless @published
      end
    end
  end
end
