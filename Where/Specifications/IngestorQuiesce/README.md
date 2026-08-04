# Ingestor quiesce

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

Exclusions: outbox save failure and retry eviction (see [`Where/TODOs.md`](../../TODOs.md)).

Run: `./tla-check IngestorQuiesce`
