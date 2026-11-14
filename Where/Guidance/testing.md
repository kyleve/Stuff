# Where testing contracts

## Testing

Root [testing conventions](../../.agents/references/swift-conventions.md#testing) apply. What is specific here:

- **Formal protocol specs** live under [`Specifications/`](../Specifications/README.md). Run them locally with [`./tla-check`](../../tla-check) (opt-in, not CI). PlusCal is the editable model source. The checker translates an isolated copy under `.build/tla/runs/` before running TLC. Each concern also holds TLC configs, a `manifest.json`, and a README tying the model to production code and cited Swift tests.
- Test bundles run in `StuffTestHost` via the `unitTests` helper in
  `Project.swift`. They link `TestHostSupport` (`show(_:perform:)`, `waitFor`).
- Use `ScriptedLocationSource` and `SwiftDataStore.inMemory()` for consumer tests.
  Test `CoreLocationSource` only through its injected fake request driver.
  Never use live location requests or the user’s on-disk/CloudKit store.
  Consumer remote-import tests use the `@_spi(Testing)`
  `inMemory(remoteChangeSource:)` + `ScriptedStoreRemoteChangeSource` seam;
  production-source history tests use isolated temporary on-disk containers
  without CloudKit (`StoreRemoteChangeSourceTests`).
- How screens render is pinned by the image snapshots in
  `WhereUI/SnapshotTests/` (the `WhereUISnapshotTests` bundle, run from the
  shared `StuffSnapshotTests` scheme + CI job, not `Stuff-iOS-Tests`). See
  [`WhereUI/AGENTS.md`](../WhereUI/Tests/AGENTS.md#testing). Do not add "hosts without
  crashing" smoke tests for surfaces those suites cover.
