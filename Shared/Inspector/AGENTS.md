# Inspector – Module Shape

Inspector is an app-agnostic developer runtime for inspecting and deleting configured filesystem, persistent UserDefaults, and SwiftData state. See [`README.md`](README.md) for the public API and behavior.

Read the root [`AGENTS.md`](../../AGENTS.md) first. That file owns build, formatting, and repository-wide conventions.

## Scope and dependencies

- **Depend only on SwiftUI, SwiftData, Foundation, Observation, QuickLook, and UIKit.** Never import Where or another app module. Applications provide every source through `InspectorConfiguration`.
- **Keep boot selection outside this module.** `InspectorModeController` persists next-launch choice and pending recovery erasures in one dedicated suite.
- **Treat the entire module as developer tooling.** Consumers compile entry points behind `#if DEBUG`. Strings remain unlocalized literals.
- **Keep `InspectorView`, `InspectorConfiguration`, `InspectorSwiftDataConfiguration`, `InspectorSwiftDataView`, and `InspectorModeController` public.** Keep other implementation types internal.

## Invariants

- **Never permit deletion of a configured filesystem root or an ancestor that contains one.**
- **Resolve every configured SwiftData source before you enable filesystem deletion.** Protect its store family, exact `recoveryStorageURLs`, and containing ancestors. If a source is unresolved, disable deletion in the unresolved storage tree.
- **Keep raw store files protected in the generic filesystem browser.** An unreadable source may erase only its explicitly configured store URL's known SQLite/support family and exact in-root `recoveryStorageURLs` through the confirmed recovery action. Remove that source from the current Inspector session only after you verify every member is absent. Latch a second-pass cleanup for the next process.
- **Complete pending recovery erasures before you construct either application runtime.** Retain failed requests and select Inspector rather than opening the regular stack against a possibly unreadable store.
- **Keep file browsing, previews, and mutations inside canonical configured roots.** Never follow a symlink outside one.
- **Enumerate only configured persistent defaults domains.** Existing scalar values may retain their type or be deleted. Complex values stay read-only. Keys cannot be created.
- **Keep every SwiftData context and model instance on `InspectorSwiftDataStore`.** Only value snapshots and persistent identifiers cross to the main actor.
- **Erase an open store through `ModelContainer.erase()`.** Remove its exact `recoveryStorageURLs`. Replace the actor's container with one reopened by the configured factory. Honor cancellation only before destructive work.
- **Expose whole-store erase from `InspectorSwiftDataConfiguration` only when its caller supplies a fresh-container factory.**
- **Keep private SwiftData reflection in [`SwiftDataReflection.swift`](Sources/SwiftDataReflection.swift).** Tables must not fault blobs or relationships merely to render.
- **Grow pagination by re-fetching one longer prefix, not offset pages.**

## Testing

Swift Testing lives in [`Tests/`](Tests), split by implementation concern. Use temporary directories, isolated defaults suites, and in-memory SwiftData containers. Image references live in [`SnapshotTests/`](SnapshotTests) and run in the shared `StuffSnapshotTests` scheme.
