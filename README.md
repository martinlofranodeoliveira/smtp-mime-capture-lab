# SMTP MIME Capture Lab

Development version **0.1.0** — an offline, receiving-only SMTP and MIME test application by [Lofrano Tecnologia](https://lofranotecnologia.com.br).

It accepts mail on literal `127.0.0.1`, commits raw bytes and envelope metadata locally, and inspects MIME in a constrained subprocess using the `mail` gem. It never delivers mail, resolves recipient domains, extracts attachments, or calls a model/API. Fixtures are synthetic. This is not an Internet mail server or a production-security claim.

[Português](README.pt-BR.md) · [Precise contract](docs/contract.md) · [Design](docs/design.md) · [Recovery](docs/recovery.md)

## Install, test, demo

Use Ruby 3.4 on an unprivileged Linux account and Bundler. Dependency installation needs RubyGems access; application scenarios run offline afterward.

```sh
bundle install
bundle exec ruby test/all_test.rb
bundle exec ruby bin/demo.rb
bundle exec ruby bin/demo.rb --json
```

The asserting demo owns a private temporary namespace, sink, independent `net-smtp` sender and inspector processes. It has a 20-second deadline, bounded output and termination/reaping paths. It deletes only its own temporary namespace. Date and Message-ID are explicit fixture bytes, not runtime-generated values.

Human output:

```text
SMTP MIME Capture Lab 0.1.0 (development)
delivery: 000001
recipients: alice@example.test, bob@example.test
text: "Olá\n.linha\n"
attachment: sample.bin (4 bytes, hex 00010203)
checks: passed
```

JSON mode includes the envelope, decoded texts, attachment hex, byte counts, SHA-256 and parser diagnostics. It contains no clock-dependent fields.

## Run a persistent local sink

Choose a new mailbox path under a trusted private parent directory:

```sh
bundle exec ruby bin/sink.rb --mailbox ./synthetic-mailbox --port 2525
```

The first stdout line is a JSON `ready` event with the numeric listening port. Use `--port 0` for an OS-assigned port. There is deliberately no host option. Stop with Ctrl-C. In another terminal:

```sh
bundle exec ruby bin/send_fixture.rb --port 2525
bundle exec ruby bin/inspect.rb --mailbox ./synthetic-mailbox
bundle exec ruby bin/inspect.rb --mailbox ./synthetic-mailbox --id 000001
bundle exec ruby bin/inspect.rb --mailbox ./synthetic-mailbox --id 000001 --json
```

Each send is a new delivery, even when bytes are identical. The inspector never extracts attachment filenames to disk. Human-readable names and text are JSON-escaped to avoid terminal control interpretation.

## Callable API

```ruby
require_relative 'lib/capture_lab'
reader = CaptureLab::MailboxReader.new('./synthetic-mailbox')
reader.list.each do |entry|
  report = CaptureLab::Inspector.delivery('./synthetic-mailbox', entry.fetch('id'))
  puts JSON.generate(report)
end
```

`reader.read('000001')` returns bounded raw bytes plus metadata. Readers share the mailbox lock with the sink; only complete published directories are visible. `Inspector.raw(bytes)` returns either `ok: true` with complete results or `ok: false` with a stable error code, never a partial success.

## Why these choices?

A small explicit SMTP state machine makes RSET, mixed recipient acceptance, SIZE, dot transparency and the final acceptance boundary inspectable. Same-filesystem directory rename publishes raw bytes and metadata together. Lifetime ownership excludes a second writer; reservations include all active stages. MIME grammar and decoding belong to a mature library, but untrusted parsing belongs in an owned, deadline/resource-limited process. See the design for the distinction between parser work and traversal limits.

## Limits and exclusions

Maximums: 4 sessions, 16 accepted recipient commands per transaction, 256 KiB raw DATA after dot removal, 100 committed-plus-reserved deliveries, 16 MiB logical payload across committed and staged files. Commands, DATA lines, headers, wire bytes, decoded aggregate bytes, depth, parts, output and time are separately bounded. SMTP supports only the documented subset, ASCII wire data and restricted ASCII envelopes. MIME inspection supports UTF-8/US-ASCII text and strict 7bit/base64/quoted-printable leaves; nested message types and encoded-word/extended filename headers are outside its subset.

No AUTH, STARTTLS, 8BITMIME, relay, DNS, antivirus, archive extraction, telemetry, exactly-once delivery, arbitrary mailbox editing, power-loss durability or standards certification. Acceptance stores opaque MIME; inspection can subsequently reject it. A disconnect after publication but before final 250 is uncertain delivery: retry can duplicate it.

## Project information

MIT, copyright 2026 Lofrano Tecnologia. Author metadata is the organization name only. Repository: [martinlofranodeoliveira/smtp-mime-capture-lab](https://github.com/martinlofranodeoliveira/smtp-mime-capture-lab). General contact: [official homepage](https://lofranotecnologia.com.br). Security reports: [private vulnerability reporting](https://github.com/martinlofranodeoliveira/smtp-mime-capture-lab/security/advisories/new).
