# Contributing

Use Ruby 3.4 on an unprivileged Linux account. Install dependencies with `bundle install`, then run:

```sh
bundle exec ruby test/all_test.rb
bundle exec ruby bin/demo.rb
bundle exec ruby bin/demo.rb --json
```

Keep scenarios offline after dependency installation. Use only synthetic example.test envelope recipients and synthetic message contents. Do not include real personal data, credentials, private client code or external delivery paths.

Changes to SMTP state, resource limits, storage layout, error codes, MIME subset or recovery behavior must update docs/contract.md and both language guides. Add independent regression fixtures with explicit expected bytes; do not generate expectations with mail itself. Keep subprocess ownership, bounded output, absolute deadlines and reaping intact. Do not replace the iterative direct-part walk with recursive convenience helpers or describe postparse guards as preparse safety.

Dependency updates should update the exact lock, review upstream notices/advisories, and recheck the Mail::Body#split! instrumentation against the actual parser. Do not add publish or deployment workflows. CI is test-only with read-only repository permissions.

Use public GitHub issues for non-sensitive defects with minimal synthetic reproduction. For vulnerabilities use the private reporting link in SECURITY.md. Contributions must be original and compatible with MIT; author metadata uses Lofrano Tecnologia without an email address.
