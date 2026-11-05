require_relative '../lib/capture_lab'
require_relative '../lib/capture_lab/mime_decoder'

STDIN.binmode
STDOUT.binmode
raw = STDIN.read(CaptureLab::Limits::RAW + 1)
result = CaptureLab::MimeDecoder.new.inspect(raw)
STDOUT.write(JSON.generate(result))
STDOUT.write("\n")
