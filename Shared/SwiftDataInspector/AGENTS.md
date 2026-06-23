# SwiftDataInspector – Module Shape

SwiftDataInspector is an app-agnostic, **read-only** SwiftData browser: hand it a
`ModelContainer` and it lists every entity with a live row count and drills into
a searchable, scrollable, **paged** table of each entity's rows and columns. Tap
a row for its full detail, and tap a relationship there to drill into the related
rows (to any depth). It works for *any* SwiftData schema because it discovers
entities, columns, values, and relationships generically (no per-app model code).
See [`README.md`](README.md) for the full narrative and usage.

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
  `entities` and exposes **async** `loadEntities()`, `rows(for:offset:)` (one
  page; `offset` powers "load more"), and `relatedRows(of:relationship:sourceType:)`
  (the detail drill-in), all delegating to the reader. Keep it thin: no store
  work belongs here.
- [`SwiftDataInspectorReader`](Sources/SwiftDataInspectorReader.swift) – a plain
  background `actor` that owns a fresh, read-only `ModelContext` per call and does
  **all** fetching, counting, reflection, relationship resolution, and value
  formatting off the main thread. Only `Sendable` snapshots cross back to the UI.
  Also home to the pure `nonisolated static` formatting/schema helpers
  (`defaultFormat`, `binaryDescription`, `columns(of:)`, `binaryColumns(of:)`,
  `relationshipColumns(of:)`, `columnCharacterCounts(...)`, `makeEntity(...)`).
- [`SwiftDataReflection`](Sources/SwiftDataReflection.swift) – the only file that
  touches SwiftData internals (see the caveat below).
- [`InspectorEntity`](Sources/InspectorEntity.swift) /
  [`InspectorRow` / `InspectorRowSet` / `InspectorRelatedRows`](Sources/InspectorRow.swift)
  – the `Sendable` snapshots returned by the reader. `InspectorEntity` carries the
  concrete metatype, the column list, and the sets of binary/relationship columns.
  `InspectorRow` carries the row's `PersistentIdentifier` (its identity, stable
  across "load more" appends and the key the detail uses to resolve relationships).
  `InspectorRowSet` also carries `columnCharacterCounts` so the view sizes columns
  without re-scanning cells on main, and reports `isTruncated` (more rows remain).
  `InspectorRelatedRows` is the resolved contents of one relationship (destination
  entity + related rows + to-many flag).
- [`EntityTableView`](Sources/EntityTableView.swift) – the per-entity detail
  table. Accumulates pages (a "Load more" footer button) and pushes a row's
  detail on tap.
- [`RowDetailView`](Sources/RowDetailView.swift) – the per-row detail: full
  attribute values plus tappable relationship rows.
- [`RelationshipView`](Sources/RelationshipView.swift) – the resolved related
  rows for one relationship (to-one drills straight in; to-many lists rows that
  drill in recursively).
- [`InspectorPreviewData`](Sources/InspectorPreviewData.swift) – `#if DEBUG`
  in-memory fixtures (Author/Book with a relationship) and the `#Preview` hosts
  for the table, the row detail, and a relationship.

## SwiftData reflection caveat

SwiftData is statically typed: `FetchDescriptor`/`fetch` need a concrete
`PersistentModel` type, and there's no public API to read an attribute by name
off a `PersistentModel` instance. [`SwiftDataReflection`](Sources/SwiftDataReflection.swift)
isolates the pieces of private-internal reflection that requires:

- the concrete metatype behind a `Schema.Entity` (`_objectType`),
- a model's stored attribute values (`_$backingData._storage`'s `lut.backing` +
  `arr`), and
- a relationship's value: its `schemaMetadata` entry carries a key path, and
  `model[keyPath:]` runs the property getter that **faults the related objects
  in** (`relatedReferences(of:named:)`). The raw backing slot can't be used here
  — before the getter runs it holds only an unresolved future
  (`DefaultStoreSnapshotValueFuture`), so the key-path access is what actually
  resolves the relationship.

**Keep all such reflection in that one file.** Every helper degrades gracefully
(returns `nil` / `[:]` / `.none`) if the private shape ever changes, so a
SwiftData update makes the inspector show blank cells or an empty relationship,
not crash. If you need more reflection, add it there with the same defensive
shape, and prefer public `Schema` API when one exists (e.g.
`Schema.Attribute.valueType` is how binary columns are detected; the existential
is opened so generic `fetch`/`fetchCount`/`schemaMetadata` infer their concrete
`PersistentModel`).

## Behaviors to preserve

- **The table never faults in blobs or relationship graphs to draw a row.**
  `Data` / `Data?` columns render as a byte count (inline storage) or a bare
  `"Data"` placeholder (external storage stays an unresolved future);
  relationships render as `"(relationship)"` without reading the slot. This keeps
  browsing a table with external-storage blobs cheap. Don't `String(describing:)`
  a relationship or resolve a blob just to format a *table* cell.
- **Relationships are faulted only on an explicit detail drill-in.** This is the
  deliberate, scoped exception to the rule above: when the user taps a
  relationship in `RowDetailView`, `relatedRows(...)` resolves it (one fault, off
  main). The table still never faults; the cost is paid only for the row the user
  asked to see. Keep relationship resolution out of the table path.
- **"Load more" is paged, not all-at-once.** The table fetches one `rowLimit`
  page at a time via `rows(for:offset:)` (`FetchDescriptor.fetchOffset`) and
  appends, so a huge table can't stall. Keep the per-page character-count merge
  (`max`) on main O(columns); the heavy per-cell scan stays in the reader.
- **All store work stays off the main thread.** Fetch, count, `Mirror`
  reflection, relationship resolution, formatting, and column character-counting
  happen on the `SwiftDataInspectorReader` actor; the main actor only renders
  `Sendable` results. `ModelContext`/`PersistentModel` aren't `Sendable`, so the
  context is created and used entirely inside the actor and never escapes — pass
  `Sendable` values (e.g. `PersistentIdentifier`, a precomputed count) into
  helpers rather than threading the context alongside a non-`Sendable` model.
  Don't move that work back onto `SwiftDataInspectorModel`.

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
  relationship *columns* (placeholder, no load), Date/Bool extraction through
  backing data, and that a refresh picks up rows written after the first load
  (proves the fresh-context reads).
- Cover pagination (`rows(for:offset:)`): later pages return disjoint slices that
  together cover every row, `isTruncated` flips on the final page, and each row
  carries a distinct `persistentID`.
- Cover relationship resolution (`relatedRows(...)`) with parent/child fixtures: a
  to-many returns the children fully materialized (their own relationships still
  placeholdered), a to-one returns the single related row, an empty relationship
  returns no rows, and a stale source id degrades to an empty result (no trap).
- Pure formatters are tested directly via the `nonisolated static`
  `SwiftDataInspectorReader.defaultFormat(...)` etc.
- Real-app wiring is covered from the consumer side: `WhereUITests` asserts the
  Where config's model types match the live schema and hosts the inspector
  against the real store.
