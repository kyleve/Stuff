# PortholeSwiftData – Module Shape

PortholeSwiftData is the `SwiftDataConnector`: a read-only Porthole connector
over a `ModelContainer`, built on SwiftDataInspector's headless reader. See
[`README.md`](README.md).

This file complements the root [`AGENTS.md`](../../../AGENTS.md) — read it first.

## Scope & dependencies

- Depends on **PortholeKit** + **SwiftDataInspector** only. It reuses the
  promoted `SwiftDataInspectorReader` (entities + paged rows) rather than
  re-implementing SwiftData reflection.
- **Read-only by construction** — the reader never mutates the store.

## Invariants

- **Register one connector per store, with an explicit `id`** (no default) — an
  app may register several, and a duplicate id is a programmer error at the
  registry.
- **Rows page via `nextCursor`** (a page-count string): the underlying reader
  returns a growing prefix, so the connector slices each page's `rowLimit`-sized
  window to keep pages disjoint. A missing/unknown `entity` filter throws
  `invalidParameters`.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PortholeSwiftDataTests`, `extraPackageProducts: [PortholeKit, PortholeCore,
SwiftDataInspector]`). In-memory container + `@Model` fixture.
