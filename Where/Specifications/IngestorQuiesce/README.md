# Ingestor quiesce

This model covers [`LocationIngestor.quiesce()`](../../WhereCore/Sources/Location/LocationIngestor.swift)
during reset.
Once quiesce completes, no sample persist may land after teardown.

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
`LocationIngestorTests.failedOutboxWriteStopsRecordingWithTheSampleStillInMemory`.
Retry eviction remains excluded from this model (see [`Where/TODOs.md`](../../TODOs.md)).

Run: `./tla-check IngestorQuiesce`
