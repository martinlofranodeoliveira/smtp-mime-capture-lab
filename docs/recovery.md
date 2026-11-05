# Protocol subset and recovery guide — English

Version 0.1.0 is a development loopback sink, not a mail-hosting service. See [contract](contract.md) for all numeric and API details.

## Transaction example

Lines below represent CRLF-terminated wire lines:

```text
EHLO synthetic.test
MAIL FROM:<fixture@example.test>
RCPT TO:<alice@example.test>
RCPT TO:<someone@outside.invalid>
DATA
```

The recipient replies are 250 then 550. DATA is still allowed because alice remains accepted. After 354, send ASCII headers, a blank line, content and a single-dot terminator. A wire body line `..linha` stores `.linha`. Final 250 occurs only after publication. RSET after MAIL/RCPT returns 250 and makes DATA return 503 until a new envelope is complete. Repeating the same accepted message allocates another ID.

Only EHLO/HELO, MAIL FROM with optional SIZE, RCPT TO, DATA, RSET, NOOP and QUIT exist. No DNS, delivery, AUTH, TLS or 8BITMIME exists. Addresses use the restricted ASCII dot-atom subset; recipient domains are exactly lowercase example.test. `MAIL FROM:<>` is supported. ASCII local-part case is preserved. Time, framing or DATA-limit failure closes instead of draining unbounded input.

## Restart outcomes

| Last completed operation | Restart visibility |
| --- | --- |
| No stage / rejected transaction | No new delivery |
| Stage written, before rename | No new delivery; recognized orphan removed |
| Directory renamed, before final 250 | One new delivery, client outcome uncertain |
| Final 250 observed | One committed delivery |

If a client retries an uncertain delivery, two IDs can contain identical messages. This is expected SMTP ambiguity, not deduplication failure. Do not infer that missing 250 means no delivery.

Startup obtains lifetime ownership before cleanup. It validates at most four orphan stages, bounded entry counts, recognized marker/files, ownership and sizes before removing anything. Unknown entries are not deleted. Missing marker, extra file, foreign ownership, symlink, over-quota state or broken committed sequence fails startup. Preserve the namespace for manual local review; do not point the sink at a directory holding other data. There is no automated repair or recursive cleanup command. Do not edit or delete committed directories behind the sink.

Fault gates `--fault before-publish` and `--fault after-publish` are explicit local test controls. A JSON fault event signals the pause; tests kill the owning sink and restart without the gate. They deliberately suspend a checkpoint and are not normal service options. The suite checks 0 exposed deliveries before publication, 1 afterward and 2 after a lost-reply retry.

Synced files and directory rename target process-crash recovery on the documented local filesystem environment. Arbitrary power loss, hardware faults, remote filesystems, disk-block exhaustion and exactly-once delivery are not promised. A crash between creating a stage directory and writing its marker can require manual review rather than automatic cleanup.
