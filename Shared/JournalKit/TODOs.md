# JournalKit todos

The item format and the placement rule live in the root
[`TODOs.md`](../../TODOs.md); raw notes go in [`INBOX.md`](../../INBOX.md), not
here.

# Open issues

## P2s (Nice to have)
- test [quick-win]: The concurrent-append test discards append errors with `try?` (`JournalTests.swift:186`). Its recovered-count, uniqueness, and per-writer-order assertions (`:194-201`) already fail when entries go missing; the old claim that missing records would pass was wrong. Surface append failures through a throwing task group so the test reports the original I/O error rather than only downstream count mismatches. (audit 2026-07-26; corrected 2026-09-07)
- fix [quick-win]: Report `.full` sync failures before callers remove recovery files — `Sources/Journal.swift:146-147` discards the result of `fcntl(F_FULLFSYNC)`. A failed sync therefore returns success from `append(_:sync:)`. The segment uses ordinary append flags (`Sources/JournalRecovery.swift:68-74`), with no separate sync fallback.

  Where now depends on this contract for its location outbox. `Where/WhereCore/Sources/Location/LocationOutbox.swift:182-185` writes an empty `.full` checkpoint before it removes the journal directory. The legacy import path at `:254-255` writes a `.full` checkpoint before it removes the old file. Both callers can therefore continue removal after the requested sync fails. This is a verified error-propagation gap, not reproduced data loss.

  If the full-sync operation fails, return a typed error that preserves `errno`. Add a fault-injection seam through `@_spi(Testing)` rather than a production parameter. Cover the sync failure, a successful retry, and unchanged `.processDeath` behavior. Verify that a failed checkpoint stops subsequent removal and preserves recoverable files.

  A failed sync can leave complete bytes in the journal, so tests must not assume rollback or exactly-once append behavior. The existing successful roundtrip (`Tests/JournalTests.swift:15`) does not prove power-loss durability. Keep that limitation explicit in the test evidence. (audit 2026-07-26; expanded by launch review 2026-10-04)

# Completed issues
