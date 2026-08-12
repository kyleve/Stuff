# JournalKit todos

The item format and the placement rule live in the root
[`TODOs.md`](../../TODOs.md); raw notes go in [`INBOX.md`](../../INBOX.md), not
here.

# Open issues

## P2s (Nice to have)
- test [quick-win]: The concurrent-append test discards append errors with `try?` (`JournalTests.swift:186`), so it would pass with fewer entries than it asserts were written. Surface the error instead. (audit 2026-07-26; re-verified 2026-08-09)
- test [quick-win]: `.full` sync durability is exercised by a single append (`JournalTests.swift:15`, inside `appendsRoundTripInOrder` — there is no dedicated `F_FULLFSYNC` regression); widen it to something that would actually catch a regression. (audit 2026-07-26; re-verified 2026-08-09)

# Completed issues
