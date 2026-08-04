# Post-write reconcile

Models the intended contract in [`DayJournal.reconcileAfterDayDataChange()`](../../WhereCore/Sources/Journal/DayJournal.swift):
commit, then full fan-out (invalidate → reminders → issue alerts → widgets), then
`changes()` readers observe applied side effects.

## Correspondence

| Model | Production |
| --- | --- |
| `writePhase` | `store.perform` transaction |
| `reconcilePhase` | sequential fan-out steps |
| `changesPinged` | `StoreChangeBroadcaster.send()` |
| `sideEffectsApplied` | badge/widgets honest |
| `readerSawPing` | subscriber refresh |

## Properties

- `NoChangesBeforeReconcileDone` — canonical path only (`Implementation = "current"`)
- `ReaderSeesAppliedSideEffects`
- `BrokenNoEarlyPing` — negative control

## Result

**Verified for these model bounds and assumptions** on `Current.cfg` for the
canonical manual-day path. `Broken.cfg` falsifies `BrokenNoEarlyPing`.

Swift guards: [`DayJournalTests.addManualDayReconcilesAndPublishes`](../../WhereCore/Tests/DayJournalTests.swift),
[`DayJournalTests.ingestPersistsAndFansOutOnce`](../../WhereCore/Tests/DayJournalTests.swift),
[`WhereServicesTests.redundantGPSSamplesSkipRepublishingButNewRegionsStillPublish`](../../WhereCore/Tests/WhereServicesTests.swift).

Single-sample ingest routes through `reconcileIssueState()` plus
`publishAfterIngest(of:)` (skips redundant widget rebuilds); bulk ingest uses
full `reconcileAfterDayDataChange()`.

Out of model until routed: `DailySummaryReconciler`, `setPrimaryRegions` (see
[`Where/TODOs.md`](../../TODOs.md) with links here). Dismiss/restore uses
widget-less `reconcileIssueState()` by design.

Run: `./tla-check PostWriteReconcile`
