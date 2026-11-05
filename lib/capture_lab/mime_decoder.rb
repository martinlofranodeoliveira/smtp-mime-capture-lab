require 'mail'
require 'base64'
require 'digest'

module CaptureLab
  module ExpansionProbe
    def split!(*args, **kwargs, &block)
      Thread.current[:capture_expansions] = Thread.current[:capture_expansions].to_i + 1
      super
    end
  end
  Mail::Body.prepend(ExpansionProbe)

  class MimeDecoder
    def initialize(decoded_limit: Limits::DECODED)
      @visited = 0
      @decoded = 0
      @decoded_limit = decoded_limit
      Thread.current[:capture_expansions] = 0
    end

    def diagnostics
      { 'visited_parts' => @visited, 'mail_body_splits' => Thread.current[:capture_expansions].to_i }
    end

    def inspect(raw)
      raw = (raw || '').b
      validate_wire(raw)
      root = Mail.new(raw)
      texts = []
      attachments = []
      stack = [[root, 0]]
      until stack.empty?
        node, depth = stack.pop
        raise Error, 'mime_depth' if depth > Limits::MIME_DEPTH
        @visited += 1
        raise Error, 'mime_parts' if @visited > Limits::MIME_PARTS
        validate_headers(node)
        type = node.mime_type.to_s.downcase
        raise Error, 'nested_message' if type.start_with?('message/')
        if node.multipart?
          raise Error, 'mime_depth' if depth >= Limits::MIME_DEPTH
          boundary = node.boundary.to_s
          if boundary.empty? || !/(?:\A|\r\n)--#{Regexp.escape(boundary)}--(?:\r\n|\z)/.match?(node.body.raw_source.to_s.b)
            raise Error, 'mime_invalid'
          end
          children = node.parts.to_a
          raise Error, 'mime_empty' if children.empty?
          if @visited + stack.length + children.length > Limits::MIME_PARTS
            raise Error, 'mime_parts'
          end
          children.reverse_each { |child| stack << [child, depth + 1] }
          next
        end
        bytes = decode_body(node)
        @decoded += bytes.bytesize
        raise Error, 'decoded_limit' if @decoded > @decoded_limit
        name = node.filename
        name = checked_name(name) if name
        attachment = name || node.content_disposition.to_s.downcase.start_with?('attachment') || !type.start_with?('text/')
        if attachment
          attachments << {
            'name' => name, 'content_type' => type, 'decoded_bytes' => bytes.bytesize,
            'sha256' => Digest::SHA256.hexdigest(bytes), 'hex' => bytes.unpack1('H*')
          }
        else
          charset = (node.charset || 'us-ascii').downcase
          encoding = case charset
                     when 'utf-8' then Encoding::UTF_8
                     when 'us-ascii' then Encoding::US_ASCII
                     else raise Error, 'charset'
                     end
          text = bytes.dup.force_encoding(encoding)
          raise Error, 'text_encoding' unless text.valid_encoding?
          text = text.encode(Encoding::UTF_8).gsub("\r\n", "\n")
          raise Error, 'text_newline' if text.include?("\r")
          texts << { 'content_type' => type, 'decoded_bytes' => bytes.bytesize, 'text' => text }
        end
      end
      {
        'ok' => true, 'texts' => texts, 'attachments' => attachments,
        'decoded_bytes' => @decoded,
        'attachment_bytes' => attachments.sum { |part| part['decoded_bytes'] },
        'diagnostics' => diagnostics
      }
    rescue Error => error
      { 'ok' => false, 'error' => error.code, 'diagnostics' => diagnostics }
    rescue StandardError
      { 'ok' => false, 'error' => 'mime_invalid', 'diagnostics' => diagnostics }
    end

    def validate_wire(raw)
      raise Error, 'raw_limit' if raw.bytesize > Limits::RAW
      raise Error, 'wire_encoding' unless raw.ascii_only? && !raw.include?("\0")
      headers = HeaderBudget.new
      raw.each_line("\r\n") do |line|
        unless line.end_with?("\r\n") && !line.byteslice(0, line.bytesize - 2).match?(/[\r\n]/)
          raise Error, 'crlf_required'
        end
        raise Error, 'line_limit' if line.bytesize > Limits::DATA_LINE
        headers.add(line)
      end
      headers.finish
    end

    def validate_headers(node)
      fields = node.header.fields
      raise Error, 'header_limit' if fields.length > Limits::HEADER_FIELDS
      total = 0
      fields.each do |field|
        value = field.value.to_s
        raise Error, 'encoded_header' if value.include?('=?') || /(?:\A|[;\s])(?:filename|name)\*/i.match?(value)
        encoded = field.encoded
        total += encoded.bytesize
        raise Error, 'header_limit' if encoded.bytesize > Limits::HEADER_FIELD || total > Limits::HEADERS
      end
    end

    def decode_body(node)
      source = node.body.raw_source.to_s.b
      transfer = (node.content_transfer_encoding || '7bit').downcase
      expected = nil
      case transfer
      when 'base64'
        compact = source.gsub("\r\n", '')
        raise Error, 'transfer_encoding' unless /\A[A-Za-z0-9+\/]*={0,2}\z/.match?(compact)
        begin
          expected = Base64.strict_decode64(compact)
        rescue ArgumentError
          raise Error, 'transfer_encoding'
        end
        raise Error, 'transfer_encoding' unless Base64.strict_encode64(expected) == compact
      when 'quoted-printable'
        index = 0
        while index < source.bytesize
          if source.getbyte(index) == 61
            following = source.byteslice(index + 1, 2)
            raise Error, 'transfer_encoding' unless following == "\r\n" || /\A[0-9A-Fa-f]{2}\z/.match?(following.to_s)
            index += 3
          else
            index += 1
          end
        end
      when '7bit'
        raise Error, 'transfer_encoding' unless source.ascii_only? && !source.include?("\0")
      else
        raise Error, 'transfer_encoding'
      end
      bytes = node.body.decoded.b
      raise Error, 'transfer_encoding' if expected && bytes != expected
      bytes
    end

    def checked_name(name)
      text = name.to_s.encode(Encoding::UTF_8)
      raise Error, 'attachment_name' unless text.valid_encoding? && text.bytesize <= Limits::NAME
      text
    rescue EncodingError
      raise Error, 'attachment_name'
    end
  end
end
