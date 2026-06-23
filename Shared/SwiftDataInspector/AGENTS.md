# SwiftDataInspector – Module Shape

SwiftDataInspector is an app-agnostic, **read-only** SwiftData browser: hand it a
`ModelContainer` and it lists every entity with a live row count and drills into
a searchable, scrollable table of each entity's rows and columns. It works for
*any* SwiftData schema because it discovers entities, columns, and values
generically (no per-app model code). See [`README.md`](README.md) for the full
narrative and usage.

This file complements the root [`AGENTS.md`](../../AGENTS.md), which owns build
system, formatting, and global conventions. Read that first.

## Scope & dependencies

- Pure **SwiftUI + SwiftData + Foundation + Observation** (plus `UIKit` only for
  font metrics in [`EntityTableView`](Sources/EntityTableView.swift)). It must
  **not** import WhereCore or any app code — it's a generic library that the
  Where app (and any future app) adopts. App-specific wiring (which container,
  which model types) lives in the consumer, passed in via
  `SwiftDataInspectorConfiguration`.
- Library target only ([`Package.swift`](../../Package.swift),
  `Shared/SwiftDataInspector/Sources`); the hosted test bundle
  `SwiftDataInspectorTests` is wired in [`Project.swift`](../../Project.swift)
  via the `unitTests` helper (host: `StuffTestHost`).
- **Intended for DEBUG / developer surfaces.** It uses contained private-API
  reflection (see below) and shows raw stored data, so consumers should gate it
  behind `#if DEBUG` (the Where app does — see
  `WhereUI/Sources/Model/WhereSession.swift` and `Settings/SettingsView.swift`).

## Public API (the whole surface)

Only two types are `public`; everything else is an internal implementation
detail.

- [`SwiftDataInspectorConfiguration`](Sources/SwiftDataInspectorConfiguration.swift)
  – the value you build the inspector from: the `container`, an optional explicit
  `modelTypes` list (falls back to reflecting the schema when `nil`), a `title`,
  a `rowLimit` (default 500, caps the page so a huge table can't stall), and a
  `@Sendable valueFormatter` override. The formatter runs on the background
  reader, so keep it pure (don't capture main-actor state).
- [`SwiftDataInspectorView`](Sources/SwiftDataInspectorView.swift) – the root
  list view. **Expects an ambient `NavigationStack`** (it pushes the per-entity
  table with a `NavigationLink`); drop it into a navigation context the consumer
  owns (a settings screen, a tab, a sheet).

## Internal types

- [`SwiftDataInspectorModel`](Sources/SwiftDataInspectorModel.swift) – the
  `@MainActor @Observable` façade the views bind to. Holds the published
  `entities` and exposes **async** `loadEntities()` / `rows(for:)` that just
  delegate to the reader. Keep it thin: no store work belongs here.
- [`SwiftDataInspectorReader`](Sources/SwiftDataInspectorReader.swift) – a plain
  background `actor` that owns a fresh, read-only `ModelContext` per call and does
  **all** fetching, counting, reflection, and value formatting off the main
  thread. Only `Sendable` snapshots cross back to the UI. Also home to the pure
  `nonisolated static` formatting/schema helpers (`defaultFormat`,
  `binaryDescription`, `columns(of:)`, `binaryColumns(of:)`,
  `relationshipColumns(of:)`, `columnCharacterCounts(...)`).
- [`SwiftDataReflection`](Sources/SwiftDataReflection.swift) – the only file that
  touches SwiftData internals (see the caveat below).
- [`InspectorEntity`](Sources/InspectorEntity.swift) /
  [`InspectorRow` / `InspectorRowSet`](Sources/InspectorRow.swift) – the
  `Sendable` snapshots returned by the reader. `InspectorEntity` carries the
  concrete metatype, the column list, and the sets of binary/relationship columns.
  `InspectorRowSet` also carries `columnCharacterCounts` so the view sizes
  columns without re-scanning cells on main.
- [`EntityTableView`](Sources/EntityTableView.swift) – the per-entity detail
  table.
- [`InspectorPreviewData`](Sources/InspectorPreviewData.swift) – `#if DEBUG`
  in-memory fixtures and the `#Preview` hosts.

## SwiftData reflection caveat

SwiftData is statically typed: `FetchDescriptor`/`fetch` need a concrete
`PersistentModel` type, and there's no public API to read an attribute by name
off a `PersistentModel` instance. [`SwiftDataReflection`](Sources/SwiftDataReflection.swift)
isolates the two pieces of private-internal reflection that requires:

- the concrete metatype behind a `Schema.Entity` (`_objectType`), and
- a model's stored values (`_$backingData._storage`'s `lut.backing` + `arr`).

**Keep all such reflection in that one file.** Both helpers degrade gracefully
(return `nil` / `[:]`) if the private shape ever changes, so a SwiftData update
makes the inspector show blank cells, not crash. If you need more reflection, add
it there with the same defensive shape, and prefer public `Schema` API when one
exists (e.g. `Schema.Attribute.valueType` is how binary columns are detected).

## Two behaviors to preserve

- **Never fault in blobs or relationship graphs to draw a row.** `Data` / `Data?`
  columns render as a byte count (inline storage) or a bare `"Data"` placeholder
  (external storage stays an unresolved future); relationships render as
  `"(relationship)"` without reading the slot. This keeps browsing a table with
  external-storage blobs cheap. Don't `String(describing:)` a relationship or
  resolve a blob just to format a cell.
- **All store work stays off the main thread.** Fetch, count, `Mirror`
  reflection, formatting, and column character-counting happen on the
  `SwiftDataInspectorReader` actor; the main actor only renders `Sendable`
  results. `ModelContext`/`PersistentModel` aren't `Sendable`, so the context is
  created and used entirely inside the actor and never escapes. Don't move that
  work back onto `SwiftDataInspectorModel`.

## Conventions

- Follow the root rules: exhaustive `switch` over enums (no bare `default:`),
  small named structs over tuples, bind SwiftUI state directly (no closure
  `Binding(get:set:)`).
- Read-only: every read uses a *fresh* throwaway `ModelContext`. Never insert,
  update, delete, or save.
- Developer-facing strings are plain literals here (no `Localizable.xcstrings`) —
  the inspector is a DEBUG tool and shouldn't pollute an app's localization
  catalog.
- Every previewable view ships a `#Preview` (see `SwiftDataInspectorView` and
  `EntityTableView`), backed by `InspectorPreviewData` in-memory fixtures.

## Testing

Tests live in [`Tests/`](Tests) (Swift Testing only, never XCTest); the bundle
runs in `StuffTestHost`. Patterns:

- Build an in-memory `ModelContainer` with local `@Model` fixtures, seed it, then
  drive `SwiftDataInspectorModel` (`await loadEntities()` / `await rows(for:)`)
  and assert on the resulting `InspectorEntity` / `InspectorRowSet`.
- Cover the generic edge cases the reflection has to survive: missing columns,
  external-storage `Data` (placeholder, no load), inline `Data` (byte count),
  relationships, Date/Bool extraction through backing data, and that a refresh
  picks up rows written after the first load (proves the fresh-context reads).
- Pure formatters are tested directly via the `nonisolated static`
  `SwiftDataInspectorReader.defaultFormat(...)` etc.
- Real-app wiring is covered from the consumer side: `WhereUITests` asserts the
  Where config's model types match the live schema and hosts the inspector
  against the real store.
