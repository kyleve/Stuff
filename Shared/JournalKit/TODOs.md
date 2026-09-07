# JournalKit todos

The item format and the placement rule live in the root
[`TODOs.md`](../../TODOs.md); raw notes go in [`INBOX.md`](../../INBOX.md), not
here.

# Open issues

## P2s (Nice to have)
- test [quick-win]: The concurrent-append test discards append errors with `try?` (`JournalTests.swift:186`). Its recovered-count, uniqueness, and per-writer-order assertions (`:194-201`) already fail when entries go missing; the old claim that missing records would pass was wrong. Surface append failures through a throwing task group so the test reports the original I/O error rather than only downstream count mismatches. (audit 2026-07-26; corrected 2026-09-07)
- test [quick-win]: `.full` sync durability is exercised by a single append (`JournalTests.swift:15`, inside `appendsRoundTripInOrder` — there is no dedicated `F_FULLFSYNC` regression); widen it to something that would actually catch a regression. (audit 2026-07-26; re-verified 2026-08-30)

# Completed issues
