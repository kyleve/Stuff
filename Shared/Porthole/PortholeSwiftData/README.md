# PortholeSwiftData

PortholeSwiftData is a [Porthole](../) connector that exposes a SwiftData store,
read-only, over the bridge — built on
[SwiftDataInspector](../../SwiftDataInspector)'s headless reader.

## Using it

```swift
import PortholeSwiftData

porthole.register(SwiftDataConnector(
    id: "swiftdata",
    title: "SwiftData",
    container: services.modelContainer,
    modelTypes: SwiftDataStore.inspectorModelTypes,   // or nil to discover from the schema
    rowLimit: 500,
))
```

Register one per `ModelContainer`; the `id` is explicit (no default) because an
app may register several.

## Surface

- Data source `entities` — one row per entity: `name`, `count`, `columns`.
- Data source `rows` — filter `entity` (required); a page of that entity's rows
  as objects keyed by column. Follow `nextCursor` for more pages (disjoint
  windows of `rowLimit` rows each).

Read-only by construction — the reader never mutates the store.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PortholeSwiftDataTests`). Uses an in-memory `ModelContainer` with a local
`@Model` fixture and asserts entity rows, paged rows via cursor, and
missing/unknown-entity rejection.
