# SwiftDataInspector

A small, app-agnostic, **read-only** SwiftData browser for SwiftUI. Point it at a
`ModelContainer` and it lists every entity with a live row count, then drills
into a searchable, scrollable table of each entity's rows and columns — for *any*
SwiftData schema, with no per-app model code.

It's built for **developer / DEBUG surfaces** (think a hidden "SwiftData
inspector" in a Settings screen): it browses raw stored data and relies on a
small amount of contained SwiftData reflection, so it's not meant to ship as
user-facing UI.

SwiftDataInspector depends only on SwiftUI + SwiftData + Foundation +
Observation (plus UIKit for font metrics) — no app code.

## What you get

- **Entity list** — every `@Model` type in the store with its live row count,
  searchable by name.
- **Per-entity table** — a lazily-rendered grid of every row's columns. The
  header pins while rows scroll vertically; the grid scrolls horizontally for
  wide schemas; rows are searchable across all cell values.
- **Load more** — the table fetches a capped page (default 500) and shows a
  footer with a **Load more** button when more rows remain, so even a huge table
  opens instantly and grows on demand. Each "load more" re-reads a longer prefix
  in one query and replaces the rows, so the visible set is always one consistent
  fetch (no overlap or skipped rows).
- **Row detail** — tap a row to see every attribute in full (selectable), and
  tap a relationship there to drill into the related rows. To-one relationships
  open the related row directly; to-many list the rows, each of which drills in
  recursively — so you can walk the object graph to any depth. A large to-many is
  capped to the same page size, and the list notes "showing N of M".
- **Generic value rendering** — strings, numbers, dates, UUIDs, and bools are
  formatted out of the box. `Data` columns show a byte count (inline) or a
  `"Data"` placeholder (external storage), and relationships show
  `"(relationship)"` in the table — **blobs and related object graphs are never
  faulted in just to draw a table row**; a relationship is resolved only when you
  explicitly drill into it from the detail.
- **Off the main thread** — all fetching, reflection, relationship resolution,
  and formatting happen on a background actor; the UI only renders `Sendable`
  snapshots.

## Installation

`SwiftDataInspector` is a local SPM library in this repo
(`Shared/SwiftDataInspector`). Add it to a target's dependencies in
[`Package.swift`](../../Package.swift):

```swift
.target(name: "YourUI", dependencies: [.target(name: "SwiftDataInspector")])
```

## Quick start

Drop `SwiftDataInspectorView` into a navigation context you own and hand it a
configuration built from your container:

```swift
import SwiftDataInspector

NavigationStack {                       // the inspector expects an ambient stack
    SwiftDataInspectorView(
        configuration: SwiftDataInspectorConfiguration(container: myModelContainer),
    )
}
```

That's it — the view loads entities on appear, pull-to-refresh re-reads, and
tapping an entity pushes its table.

> The view pushes the per-entity table with a `NavigationLink`, so it **must**
> have a `NavigationStack` (or other navigation destination context) above it.
> It deliberately doesn't wrap itself in one, so it composes inside a settings
> screen, a tab, or a sheet. (It uses closure `NavigationLink`s and
> `navigationDestination(item:)` rather than value-based routing, so it pushes
> correctly no matter how the host presents it.)

## Configuration

```swift
public struct SwiftDataInspectorConfiguration {
    public init(
        container: ModelContainer,
        modelTypes: [any PersistentModel.Type]? = nil,  // nil → reflect the schema
        title: String = "SwiftData",                    // root list navigation title
        rowLimit: Int? = 500,                           // nil → fetch every row
        valueFormatter: (@Sendable (Any) -> String?)? = nil,
    )
}
```

- **`modelTypes`** — pass your types explicitly to skip the schema reflection
  fallback (and to control ordering/inclusion). When `nil`, the inspector derives
  the entity list from `container.schema`.
- **`rowLimit`** — the page size, so a huge table can't stall the UI. The table
  loads the first page, shows how many of the total are loaded, and offers a
  **Load more** button to grow the window; it also caps how many related rows a
  relationship drill-in materializes. `nil` fetches everything at once (no button,
  no cap).
- **`valueFormatter`** — override how a raw stored value becomes display text;
  return `nil` to fall back to the built-in formatting. It runs on a background
  actor, so it's `@Sendable` — keep it pure:

```swift
SwiftDataInspectorConfiguration(container: container) { value in
    (value as? Data).map { "blob(\($0.count))" }   // else nil → built-in
}
```

## How it works

The inspector is generic because it discovers everything at runtime:

1. **Entities** come from `container.schema.entities` (or the explicit
   `modelTypes`). Each entity's columns are its attributes followed by its
   relationships.
2. **Rows** are fetched as a growing prefix with a type-erased `FetchDescriptor`
   (`fetchLimit` = `pageCount × rowLimit`); "load more" raises the count and
   replaces the rows with the longer, single-fetch prefix (so pages can't overlap
   or skip even without a sort). Each model's stored values are read by name via a
   small, well-contained reflection over SwiftData's backing data, and each row
   keeps its `PersistentIdentifier` as a stable identity.
3. **Values** are formatted to display strings. Binary and relationship columns
   are rendered as lightweight placeholders so external-storage blobs and related
   graphs are never materialized to draw the table.
4. **Drill-in** resolves a relationship only when you tap it: the source row is
   re-fetched by id, the relationship's property getter is run (via its
   `schemaMetadata` key path) to fault the related objects, and the related rows
   (capped to `rowLimit`) are fetched fully materialized in a single batch query —
   then rendered with the same placeholder rules, so you can keep drilling.

SwiftData has no public API to read an attribute (or a relationship) by name off
a `PersistentModel`, so those steps use private-internal reflection — isolated to
a single file and written to **degrade gracefully** (blank cells / an empty
relationship, never a crash) if a future SwiftData release changes the internal
shape.

### Threading

`SwiftDataInspectorModel` is a thin `@MainActor @Observable` façade; the real
work lives on a background `SwiftDataInspectorReader` actor that owns a fresh,
read-only `ModelContext` per call. Because `ModelContext`/`PersistentModel`
aren't `Sendable`, the context never leaves the actor — only `Sendable` snapshots
(`InspectorEntity`, `InspectorRowSet`, `InspectorRelatedRows`) come back to the
UI. The result: opening even a 500-row entity (or resolving a relationship) does
its DB fetch and reflection off main, and the main thread only renders (showing a
`ProgressView` while loading).

### Freshness

Every load uses a new `ModelContext`, and both the list and the detail are
`.refreshable`, so the inspector reflects rows written after it opened.

## Read-only by design

The inspector only ever reads — it never inserts, updates, deletes, or saves.
There is currently no editing capability.

## Example: adopting it in an app (Where)

The Where app exposes it behind a DEBUG-only entry point in its floating
developer overlay. It surfaces the live container and model types through narrow
accessors (without widening its SwiftData-free store boundary) and builds a
configuration:

```swift
#if DEBUG
extension WhereSession {
    var swiftDataInspectorConfiguration: SwiftDataInspectorConfiguration? {
        guard let container = services.modelContainer else { return nil }
        return SwiftDataInspectorConfiguration(
            container: container,
            modelTypes: SwiftDataStore.inspectorModelTypes,
            title: "SwiftData",
        )
    }
}
#endif
```

```swift
#if DEBUG
if let configuration = session.swiftDataInspectorConfiguration {
    NavigationLink("SwiftData inspector") {
        SwiftDataInspectorView(configuration: configuration)   // ambient stack from the developer tools screen
    }
}
#endif
```

## Testing

The module is exercised with Swift Testing in a hosted test bundle. Build an
in-memory `ModelContainer` with local `@Model` fixtures, seed it, drive
`SwiftDataInspectorModel` (`await loadEntities()` / `await rows(for:pageCount:)` /
`await relatedRows(...)`), and assert on the snapshots — covering the generic edge
cases the reflection must survive (missing columns, inline vs. external `Data`,
relationship columns, Date/Bool extraction, refresh picking up newly written
rows), pagination (a growing prefix that covers every row with stable, distinct
`persistentID`s and flips `isTruncated`), and relationship resolution (to-many,
to-many capped to `rowLimit` with the true `totalCount`, to-one, empty/nil, and a
stale source id that degrades instead of trapping).

How the inspector *renders* is pinned by image snapshots in
[`SnapshotTests/`](SnapshotTests), with reference images under
`SnapshotTests/__Snapshots__/` in Git LFS. They build the same kind of local
in-memory fixture schema and apply no design-system root, so the capture shows
what a consumer actually gets rather than any one host app's styling. They build
as the module's own `SwiftDataInspectorSnapshotTests` bundle, which runs
alongside every other module's image suite in the shared `StuffSnapshotTests`
scheme. Run with `./test
--snapshots`; to re-record after an intentional UI change, see the
[SnapshotKitTesting README](../SnapshotKitTesting/README.md#recording).
