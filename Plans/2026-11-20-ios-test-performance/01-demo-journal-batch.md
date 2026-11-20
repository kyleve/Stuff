# 01. Publish the completed demo dataset once

Status: executing. Reviewed on November 20 at `798c61cc4`. Independent of plan 02.

## Outcome and method

US-01 / R-01. Open demo mode and run its fixtures faster while preserving all stored days, device attribution, audit records and the final widget. The 12-test demo suite seeded 51 stores in 30.194 seconds locally. Its 233 widget publishes accounted for 16.26 seconds. A targeted Time Profiler sample placed 4.672 seconds under both widget publishing and polygon containment.

1. Use the existing day journal and store transaction. Build the same samples, backfills and corrections, preserve their order, device and dates, and write them before the single derived-state refresh. Retain single-entry semantics for other callers.
2. Exercise mixed additive and authoritative overlays, individual audits, final widget contents and publication count. Verify a partial write cannot publish or commit an incomplete batch. Retain the issue-category matrix.
3. Run `./test --only WhereCoreTests/DemoDataBuilderTests --only WhereCoreTests/DayJournalTests` and other affected tests. Compare the demo suite alone on Xcode 27.2 with the same baseline and count completed publishes. Repeat unprofiled timing, separate observed seconds from projected CI cost, and discard the change if correctness fails.

```mermaid
flowchart LR
    Seed[DemoDataBuilder] --> Journal[DayJournal batch]
    Journal --> Write[Generation-scoped store transaction]
    Write -->|Commit succeeds| Refresh[Reconcile issues and publish widget]
```

In Swift terms, the seed supplies device-stamped samples and ordered manual day values to one journal operation. The journal awaits the store transaction, then calls its existing reconciliation method. X-01 excludes new persistence formats, changes to single-record writes and bypassing production services in the tests.

## Execution record

The demo implementation agent owns this change on `perf/demo-journal-batch`. The primary agent owns independent review and publication into `main`. Resume with the mixed batch and rollback checks.
