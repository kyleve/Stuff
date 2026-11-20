# 01. Publish the completed demo dataset once

Status: complete. Published in [PR 549](https://github.com/kyleve/Stuff/pull/549). Reviewed on November 20 at `798c61cc4`. Independent of plan 02.

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

Implemented at `1d1183c66`. The seed sets primary regions as before, then sends device-stamped GPS and ordered manual day values through one generation-scoped transaction. The same journal reconciliation publishes the completed data. An injected correction-write failure rolled back GPS and manual entries and published nothing.

| Unprofiled local measurement | Main | Candidate |
| --- | ---: | ---: |
| 12 demo tests | 32.510 s | 16.765 s |
| Issue-category test, both dates and all 32 combinations | 18.772 s | 9.678 s |
| Completed widget publishes across 51 seeds | 233 | 51 |
| Time inside those publishes | 17.455 s | 2.510 s |

The same iPhone 17 simulator on iOS 27.2 ran both revisions. The isolated suite saved 15.745 seconds (48.4%). Two other candidate runs took 16.824 and 18.146 seconds. These are local suite timings.

`./test --no-generate --only WhereCoreTests/DemoDataBuilderTests --only WhereCoreTests/DayJournalTests --only WhereCoreTests/WhereServicesTests --only WhereCoreTests/WidgetSnapshotPublisherTests` passed 96 tests plus the wrapper's architecture and host checks. The two new regression cases detected intermediate widget publications and partial persisted writes on main. Independent review found a missing per-entry audit assertion. The final standalone runs also verified each stored timestamp, note and location. SwiftFormat lint and diff checks passed.

[Implementation PR](https://github.com/kyleve/Stuff/pull/549) · [STU-203](https://linear.app/kve/issue/STU-203)
