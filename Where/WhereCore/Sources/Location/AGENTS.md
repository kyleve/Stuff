# Location acquisition and outbox contracts

Read the [module contract](../../AGENTS.md) and the [repository contract](../../../../AGENTS.md) first.

- **`LocationSource` abstracts GPS.** `CoreLocationSource` runs in production.
  `ScriptedLocationSource` runs in tests/previews. `requestCurrentLocation()`
  returns a typed, nonthrowing outcome and coalesces concurrent waiters without
  coupling their cancellation. Reject negative accuracy everywhere. Apply the
  1 km, 60-second, and boundary-confidence gates only in
  `CurrentRegionResolver`; retain other valid passive samples. It backs
  `LocationIngestor.captureTodayIfNeeded(now:)`. Keep the one-shot system
  controls behind `CurrentLocationRequestDriving`, with a conforming fake in
  `CoreLocationSourceTests`. Keep coalesced waiters and their timeout in one
  idle/pending request state; finish each waiter exactly once.
- **Journal complete `LocationOutbox` snapshots through `JournalKit`.** Stamp
  every entry with its authorizing data generation. Never replay it into
  another generation. Keep the directory excluded from device backups. Make a
  destructive clear durable before removing old segments. Guards:
  `LocationOutboxTests` and
  `LocationIngestorTests.failedOutboxWriteStopsRecordingWithTheSampleStillInMemory`.
