# WhereCore test and fixture contracts

Read the [module contract](../AGENTS.md) and [repository contract](../../../AGENTS.md) first.

## Testing

Swift Testing in [`Tests/`](.) (`WhereCoreTests`), hosted in
`StuffTestHost`. Drive collaborators against `SwiftDataStore.inMemory()` +
`ScriptedLocationSource`. Never use the user's on-disk/CloudKit store or live
Core Location requests. Keep production-source history tests in isolated
temporary on-disk containers without CloudKit (`StoreRemoteChangeSourceTests`).
`CoreLocationSourceTests` must replace the source’s
one-shot controls with a `CurrentLocationRequestDriving` fake before requesting
a fix; never start passive monitoring in those tests. The CloudKit remote-import path uses the
`@_spi(Testing)` `inMemory(remoteChangeSource:)` +
`ScriptedStoreRemoteChangeSource`. Internal types are reached via
`@testable import WhereCore`.

Keep raw flight archives and export configurations outside Git. Preserve the complete selected GPS window before minimizing a regression.
Verify transformation fidelity with `FlightFixtureExporterTests` and write expected flight behavior independently of detector output.
Require explicit `coordinateMode: preserve` to export original coordinates. Keep coordinate provenance in the JSON fixture's `coordinates` field.
Keep recorded windows in `Tests/Fixtures/Flights/` as `RecordedFlightFixture` JSON. Load them from the test bundle and keep expected behavior in Swift tests.
The [recorded-fixture procedure](../README.md#recorded-flight-fixtures) covers extraction and publication.

`InMemoryKeyValueStore` and the noop schedulers/refreshers are plain `public`
production API, not test scaffolding. Demo mode assembles a session out of
them. Do not restore the `@_spi(Testing)` + `#if DEBUG` gating the first two
once carried (#150).

The notification and widget seams run the other way round from most defaults
here. The `@_spi(Testing)` `init` defaults them to the **no-ops**. The
public `make(...)` requires them. The reconcilers behind them fire on ordinary
writes. A suite that named nothing would schedule real notifications and
reload the user's widget timelines as a side effect of saving a day. Only
`WhereBootstrap` names the real ones. `forIntents(sharingStoreOf:)` inherits
them from its base for the same reason it inherits the attributor. A stack
derived from the demo world must stay made of no-ops.
