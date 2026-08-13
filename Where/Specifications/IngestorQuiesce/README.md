# Ingestor quiesce

The side-by-side Lean prototype in `Model.lean`
kernel-proves the current safety properties over every reachable state and
checks the broken trace. Run it with `./lean-check IngestorQuiesce`; TLC remains
checked in while repository-wide fairness/deadlock parity is open.

Models [`LocationIngestor.quiesce()`](../../WhereCore/Sources/Location/LocationIngestor.swift)
during reset: once quiesce completes, no sample persist may land after teardown.

## Correspondence

| Model | Production |
| --- | --- |
| `acceptsSamples` | ingest gate shut by quiesce |
| `inFlightPersist` | persist await boundary |
| `quiescePhase` | idle → begin → awaiting → done |
| `postQuiescePersist` | any persist completing while `done` |

## Properties

- `NoAcceptAfterQuiesceBegin`
- `NoPersistAfterQuiesceDone` (`~postQuiescePersist`)
- `MonitoringOffAtQuiesceDone`

## Result

**Verified for these model bounds and assumptions** on `Current.cfg`.
`Broken.cfg` (accepts samples through quiesce) falsifies `NoPersistAfterQuiesceDone`.

Swift guard: [`LocationIngestorTests.quiesceStopsPersistingFurtherSamples`](../../WhereCore/Tests/LocationIngestorTests.swift).

Outbox save failure is covered by
`LocationIngestorTests.failedOutboxWriteStopsRecordingWithTheSampleStillInMemory`. Retry eviction
remains excluded from this model (see [`Where/TODOs.md`](../../TODOs.md)).

Run: `./tla-check IngestorQuiesce`
