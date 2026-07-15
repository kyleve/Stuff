# WhereCore – Module Shape

WhereCore is the domain layer of the Where feature: the persistence boundary,
GPS ingestion, per-day / per-year aggregation, data-quality detection, and the
side effects that hang off a committed write (reminders, widgets, backup,
on-device activity summaries). It is assembled behind one `Sendable` value —
`WhereServices` — that the UI and widgets talk to. See [`README.md`](README.md)
for the public API and how the pieces fit.

The **domain/presentation split and the rules WhereCore must uphold** (the
`WhereServices` entry point, `WhereStore.perform` writes, the single
read-refresh signal, `WhereLog` logging, `LocationSource`, `ManualEntryAudit`)
live in the feature [`Where/AGENTS.md`](../AGENTS.md#layering) — read that and
the root [`AGENTS.md`](../../AGENTS.md) first. This file adds only the module's
internal shape.

## Scope & dependencies

- **Pure Swift + Foundation + SwiftData + CoreLocation + FoundationModels**,
  plus [`RegionKit`](../RegionKit) (region lookup) and
  [`LogKit`](../../Shared/LogKit); `ZIPFoundation` backs the backup archive. It
  must **not** import SwiftUI or UIKit — if a behavior would still be correct
  without SwiftUI, it belongs here, not in `WhereUI`.
- Library target in [`Package.swift`](../../Package.swift)
  (`Where/WhereCore/Sources`); depended on by `WhereUI` and the `WhereWidgets`
  extension. User-visible error strings ship in its own
  `Sources/Resources/Localizable.xcstrings` (`bundle: .module`).

## Shape & invariants

- **`WhereServices` is the composition root**, not a god-object. It wires the
  focused, single-responsibility collaborators (`ReportReader` reads,
  `DayJournal` writes, `LocationIngestor` GPS, `DataIssueScanner` detection, the
  reminder / summary / issue-alert reconcilers, `WidgetSnapshotPublisher`,
  `BackupCoordinator`, `RecentActivitySummarizer`) and owns the one
  cross-collaborator operation, `reset()`. Add new behavior to the collaborator
  it belongs to.
- **`WhereStore` is a value-type boundary.** Everything crossing it is a value,
  never a SwiftData record; every mutation runs inside `perform { … }` (the
  production `SwiftDataStore` traps otherwise), and each committed transaction
  pings `changes()` — the single signal readers refresh from. The live
  `ModelContainer` is surfaced only for the read-only debug inspector.
- **Writes await their side effects.** `DayJournal` commits, then awaits the
  reminder reconcile + widget publish in sequence, so a reader on the next
  `changes()` ping never observes a half-applied write. `DataIssueScanner` drops
  its cache on the same signal *and* is invalidated inline where a caller needs
  it provably fresh (see `WhereServices.reset()`), which is the deterministic
  half of that pair, not redundant with it.
- **`LocationSource` abstracts GPS.** Production is `CoreLocationSource` (Visits
  + significant-change); tests/previews use `ScriptedLocationSource`. The
  one-shot `requestCurrentLocation()` returns `nil` (never throws) when no fix
  is available — it only stamps a manual entry's audit trail.
- **Impossible states trap; recoverable ones surface.** `WhereStore` methods are
  `async throws` so the CloudKit-backed store can report I/O failure; a `catch`
  must log via `WhereLog.channel(_:)` (typed `Category`, PII-free) and leave
  state honest — never swallow into an empty default.

## Testing

Swift Testing in [`Tests/`](Tests) (`WhereCoreTests`), hosted in `StuffTestHost`.
Drive collaborators against `SwiftDataStore.inMemory()` + `ScriptedLocationSource`
— never the on-disk/CloudKit store or `CoreLocationSource`. The CloudKit
remote-import path uses the `@_spi(Testing)` `inMemory(remoteChangeSource:)` +
`ScriptedStoreRemoteChangeSource`. Internal types are reached via
`@testable import WhereCore`. `InMemoryKeyValueStore` (the `KeyValueStore` test
double) ships here behind `@_spi(Testing)` + `#if DEBUG` — not in a test-only
module — so it never ships in release; test bundles get it with
`@_spi(Testing) import WhereCore`.
