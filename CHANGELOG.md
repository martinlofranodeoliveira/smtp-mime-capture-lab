# Changelog

## 0.1.0 — Unreleased

Development version; no deployment or adoption claims.

- Loopback-only SMTP subset with explicit transaction state, SIZE, CRLF and dot transparency.
- Private mailbox stages, lifetime ownership, locked byte/slot reservations and atomic publication.
- Committed-state serial IDs, bounded orphan recovery and explicit lost-250 uncertainty.
- Callable mailbox reader and constrained mail-based MIME inspector with strict supported encodings, byte counts, hex and SHA-256.
- Independent synthetic net-smtp sender, deterministic asserting demo and regression/adversarial tests.
- English and Portuguese usage, protocol-subset and recovery documentation.

- Keep owned child leaders unreaped while draining output and never signal a PID/group after collecting it; preserve timeout and output-cap cleanup.
