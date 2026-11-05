# Security policy

This is development version 0.1.0 of a restricted local testing application, not a hardened Internet SMTP server. There is no AUTH, TLS, antivirus, attachment execution, external delivery, telemetry or production-security claim. Do not expose it through proxies or port forwarding. A loopback port is accessible to other local processes; loopback is not authentication.

Report vulnerabilities privately through GitHub private vulnerability reporting:

https://github.com/martinlofranodeoliveira/smtp-mime-capture-lab/security/advisories/new

Do not put sensitive reports, real mail, personal data or secrets in public issues. Supply a minimal synthetic fixture, Ruby/platform details, command and expected/observed behavior. No response-time SLA is asserted. General contact is the official homepage: https://lofranotecnologia.com.br

Threat boundaries and limitations:

- The mailbox parent and same-UID processes are trusted. Private permissions and no-follow checks are not a sandbox against that UID or a compromised filesystem.
- MIME remains untrusted. Parsing occurs in an owned resource-limited worker, but traversal guards do not prove that parser work never precedes them. Resource failures are inspection errors, not partial success.
- Attachment names, headers, JSON metadata and decoded bodies are data. Never render them as trusted HTML, execute them, or use names as extraction paths in downstream tools.
- Quotas measure logical owned file payload, not filesystem allocation or journal space. Kernel I/O stalls and arbitrary hardware/power failure are outside the contract.
- A missing final 250 can mean uncertain delivery and retry can duplicate. There is no exactly-once promise.

Only the documented 0.1.0 development contract is in scope; this policy does not assert long-term support, certification or a security audit.
