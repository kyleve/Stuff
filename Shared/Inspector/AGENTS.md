# Inspector – Module Shape

Inspector is an app-agnostic developer runtime for inspecting and deleting
configured filesystem, persistent UserDefaults, and SwiftData state. See
[`README.md`](README.md) for the public API and behavior.

This file complements the root [`AGENTS.md`](../../AGENTS.md), which owns build,
formatting, and repository-wide conventions.

## Scope and dependencies

- Depend only on SwiftUI, SwiftData, Foundation, Observation, QuickLook, and
  UIKit. Never import Where or another app module; applications provide every
  source through `InspectorConfiguration`.
- Keep boot selection outside this module. `InspectorModeController` only
  persists the next-launch choice in a dedicated suite.
- Treat the entire module as developer tooling. Consumers compile entry points
  behind `#if DEBUG`; strings remain unlocalized literals.
- Keep `InspectorView`, `InspectorConfiguration`,
  `InspectorSwiftDataConfiguration`, `InspectorSwiftDataView`, and
  `InspectorModeController` public. Other implementation types stay internal.

## Invariants

- Never permit deletion of a configured filesystem root.
- Resolve every configured SwiftData source before enabling filesystem
  deletion; protect its store family and containing ancestors, or disable
  deletion in the unresolved storage tree.
- Keep raw store files protected in the generic filesystem browser. An
  unreadable source may erase only its explicitly configured store URL's known
  SQLite/support family through the confirmed recovery action, then must reopen
  through its container factory.
- Keep file operations inside canonical configured roots; never follow a
  symlink outside one.
- Enumerate only configured persistent defaults domains. Existing scalar values
  may retain their type or be deleted; complex values stay read-only and keys
  cannot be created.
- Keep every SwiftData context and model instance on
  `InspectorSwiftDataStore`; only value snapshots and persistent identifiers
  cross to the main actor.
- Erase an open store through `ModelContainer.erase()`, then replace the
  actor's container with one reopened by the configured factory.
- Keep private SwiftData reflection in
  [`SwiftDataReflection.swift`](Sources/SwiftDataReflection.swift). Tables must
  not fault blobs or relationships merely to render.
- Grow pagination by re-fetching one longer prefix, not offset pages.

## Testing

Swift Testing lives in [`Tests/`](Tests), split by implementation concern.
Use temporary directories, isolated defaults suites, and in-memory SwiftData
containers. Image references live in [`SnapshotTests/`](SnapshotTests) and run
in the shared `StuffSnapshotTests` scheme.
