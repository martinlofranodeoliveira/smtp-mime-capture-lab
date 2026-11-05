# Dependency scope and licenses

Application author: Lofrano Tecnologia. Application code is original MIT code; gem implementations are dependencies, not copied source.

Gemfile.lock records exact versions. Install with Bundler; no dependency is downloaded by the running sink, sender or inspector. The test environment requires Ruby 3.4. The mail gem is loaded only inside the decoder process; net-smtp is used only by the independent sending fixture. Minitest is test-only.

Direct dependencies:

- mail 2.9.1: MIT; MIME parsing/decoding. Source: https://github.com/mikel/mail
- net-smtp 0.5.2: Ruby/BSD-2-Clause licensing; synthetic independent SMTP client. Source: https://github.com/ruby/net-smtp
- base64 0.2.0: Ruby/BSD-2-Clause; explicit bundled gem dependency for Ruby 3.4. Source: https://github.com/ruby/base64
- minitest 5.27.0: MIT; tests. Source: https://github.com/minitest/minitest

Locked transitives:

- logger 1.6.4: Ruby/BSD-2-Clause, https://github.com/ruby/logger
- mini_mime 1.1.5: MIT, https://github.com/discourse/mini_mime
- net-imap 0.5.15: Ruby/BSD-2-Clause, https://github.com/ruby/net-imap
- net-pop 0.1.2: Ruby/BSD-2-Clause, https://github.com/ruby/net-pop
- net-protocol 0.2.2: Ruby/BSD-2-Clause, https://github.com/ruby/net-protocol
- timeout 0.4.3: Ruby/BSD-2-Clause, https://github.com/ruby/timeout
- date 3.4.1: Ruby/BSD-2-Clause, https://github.com/ruby/date

The mail dependency graph includes IMAP/POP support, but this application never uses those clients. Ruby/BSD-2-Clause denotes upstream's alternative license choices, not MIT relicensing by this project. Retain upstream notices when redistributing gems. Review the installed gem license files and dependency advisories when changing the lock; the application MIT license does not supersede them. No certification or dependency-security guarantee is asserted.
