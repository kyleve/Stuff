# StorageKit – Module Shape

StorageKit is an app-agnostic library for **containerized, mode-aware storage**: a
`StorageSystem` vends a tree of `StorageContainer`s, each owning one directory and
vending raw files, a namespaced key-value store, and an isolated SwiftData
`ModelContainer`. One `mode` switch makes the whole tree persistent or in-memory,
and two registration-based, children-first teardown paths cleanly stop or destroy
any subtree. See [`README.md`](README.md) for the narrative and usage.

This file complements the root [`AGENTS.md`](../../AGENTS.md), which owns build
system, formatting, and global conventions. Read that first.

## Scope & dependencies

- Pure **Foundation + SwiftData**. It must **not** import UIKit/SwiftUI, app code
  (WhereCore/WhereUI), or `LifecycleKit` — a consumer that wants a teardown step
  wraps a `deactivate()` / `deleteContainer()` call in its own `LifecycleStep`,
  keeping the two decoupled.
- Library target only ([`Package.swift`](../../Package.swift),
  `Shared/StorageKit/Sources`); the hosted test bundle `StorageKitTests` is wired
  in [`Project.swift`](../../Project.swift) via the `unitTests` helper (host:
  `StuffTestHost`).
- Not yet adopted by the Where app — this is a standalone module. Migrating
  Where's ad-hoc storage (`LocationOutbox`, `WidgetSnapshotStore`,
  `SwiftDataStore`, `WherePreferences`) onto it is a future pass.

## Key types

- [`StorageSystem`](Sources/StorageSystem.swift) – the **root**: an `actor` that
  is pure configuration (`mode`, resolved namespace `url`, injected
  `FileManager`) plus a vending point. It owns no storage logic of its own — it
  creates its namespace directory and delegates `container` / `deactivate` /
  `deleteAll` to a private root `StorageContainer`.
- [`StorageContainer`](Sources/StorageContainer.swift) – the **node**, and where
  everything happens: an `actor` holding a child registry, cached vends, and
  teardown registrations. `key` / `url` / `mode` / `suiteName` are
  `nonisolated let`. Children are `StorageContainer`s (recursive); the parent
  back-reference is `weak` so a deleted subtree releases.
- [`StorageKey`](Sources/StorageKey.swift) – a sanitized single path component
  (`Hashable`, `ExpressibleByStringLiteral`, `init(some RawRepresentable<String>)`).
- [`BaseDirectory`](Sources/BaseDirectory.swift) – where a persistent system
  roots (`applicationSupport` / `caches` with optional `subdirectory`, or
  `custom`); `resolvedURL(using:)` is public so a `.custom` base can be built from
  a standard one.
- [`StorageMode`](Sources/StorageMode.swift) / [`CloudKitOption`](Sources/CloudKitOption.swift)
  / [`StorageError`](Sources/StorageError.swift) – the mode switch, the CloudKit
  pass-through (`.none` / `.automatic`), and the typed error
  (`containerDeleted`).
- [`KeyValueStore`](Sources/KeyValueStore.swift) – a minimal, `Sendable`-clean
  protocol (typed `bool/int/double/string/data`, no `Any?`) with two conformers:
  `UserDefaultsKeyValueStore` (`@unchecked Sendable` wrapper around a suite) and
  the public `InMemoryKeyValueStore` (lock-guarded, typed slots).

## Behaviors to preserve

- **Root vs. node split.** Keep `StorageSystem` config-only; do not add storage
  operations there. New per-node behavior goes on `StorageContainer`.
- **Vends are cached and idempotent.** `container(_:)`, `keyValueStore()`, and
  `modelContainer(for:)` return the same instance per node until the cache is
  dropped by teardown. This is load-bearing for `ModelContainer` (never two on one
  file) — don't make any vend construct a fresh instance each call.
- **In-memory does the right thing automatically.** `.inMemory` mode roots in a
  temp directory, vends `InMemoryKeyValueStore`, and builds the SwiftData store
  `isStoredInMemoryOnly` with **CloudKit forced off**. Callers use identical code
  in both modes — keep that invariant when touching the vends.
- **Each SwiftData store gets its own child directory.** `modelContainer(for:)`
  vends a dedicated child (`named`, default `"store"`) and places the store at
  `<child>/<named>.store`, so the db + `-wal`/`-shm` + external blobs are isolated
  and deletable as a unit. Don't put a store directly in a shared directory.
- **Two teardown paths, never a flag.** `deactivate()` (reversible: run
  `onDeactivate` + drop cached vends, keep files, go `inactive`, reactivate on
  re-vend) and `deleteContainer()` (destructive). Don't collapse them into a
  `tearDown(delete:)` boolean.
- **Deletion order and park-safety.** `deleteContainer()` runs children-first:
  `prepareForDeletion` (resources live) → `deactivate` (`onDeactivate` + drop
  vends) → remove directories **and** key-value suites + deregister →
  `afterDeletion`. Everything before the remove must be reversible so a throw
  parks with the subtree intact (retry-safe); only `afterDeletion` may run after
  the point of no return, and a throw there retries just that step. Preserve this
  ordering and the "nothing deleted on an early throw" guarantee.
- **State is one enum.** `State` is `active` / `inactive` /
  `deleting(wasActive:)` / `deleted` (no loose flags); vending reactivates an
  `inactive` node and throws/traps on a `deleting` or `deleted` one;
  `deactivate()` is a no-op when already `inactive`. `deleting` is the in-flight
  teardown state that makes the subtree reject vends so a race can't resurrect a
  directory mid-delete. Its `wasActive` payload records the pre-freeze state so
  `onDeactivate` fires exactly once (skipped when the node was already
  `inactive`, since it ran during that `deactivate()`) and a pre-commit throw
  reverts to the *exact* prior resting state (`active` or `inactive`);
  committing advances it to `deleted`. Keep invalid states unrepresentable per
  the root rules.
- **Errors surface.** Vending/teardown throw `StorageError` or rethrow the
  underlying `FileManager`/SwiftData error — never swallow into an empty default.
  The one deliberate exception is the **non-throwing `keyValueStore()`**, which
  *traps* (not throws) when called on a `deleting`/`deleted` node. This keeps
  reads terse; it's a genuine programmer error (vending while/after a delete is a
  lifecycle bug), so don't make callers `try`/`catch` it — preserve the
  non-throwing signature and the trap, and route through the throwing
  `container(_:)` / `modelContainer(for:)` when a recoverable failure is wanted.
- **Key-value suites live outside the directory.** Because a `UserDefaults` suite
  isn't under the container's directory, deletion must `removePersistentDomain`
  per node (it does, in the purge phase). If you change suite naming, keep it
  hierarchical, stable, and purged on delete.

## Conventions

- Follow the root rules: exhaustive `switch` over enums (no bare `default:`),
  small named structs over tuples, typed keys not raw `String`s, `@_spi`/internal
  for testing-only access, and "never silently swallow errors."
- `FileManager` is injected into `StorageSystem` (mirroring
  `FileLocationOutbox.applicationSupport(fileManager:)`) for resolving the base
  and creating the namespace directory; containers use `FileManager.default` for
  their own I/O. Test determinism comes from `base: .custom(tempDir)`, not from
  threading a mock `FileManager` through every actor (which would fight Sendable).
- Concurrency: both types are `actor`s; cross-actor reads use `nonisolated let`.
  Teardown handlers are `@Sendable () async throws -> Void` (`TeardownHandler`).

## Testing

Tests live in [`Tests/`](Tests) (Swift Testing only, never XCTest), 1:1 with
sources, hosted in `StuffTestHost`. Shared fixtures (the `Note` `@Model`, a
`CallLog` actor, a `ThrowOnce` actor, `makeTemporaryDirectory()`) live in
[`StorageKitTestSupport.swift`](Tests/StorageKitTestSupport.swift). Patterns:

- Always use `base: .custom(makeTemporaryDirectory())` (+ `defer` cleanup) so a
  test never touches the host's real Application Support or Caches.
- Assert tree shape via the on-disk directories (`FileManager.fileExists`) and
  identity via `===` on the vended actors / objects.
- Drive teardown ordering with a `CallLog` actor recording `phase:node` strings
  and assert the exact children-first sequence.
- Drive park-safety with a `ThrowOnce` actor in a handler: assert the first call
  throws and leaves data intact (or, for `afterDeletion`, deletes it), and the
  retry completes.
- Read lifecycle transitions through `@testable import StorageKit` and the
  internal `state` property; the `UserDefaultsKeyValueStore` wrapper is internal,
  so its test also needs `@testable`.

Consider these rules if they affect your changes.
