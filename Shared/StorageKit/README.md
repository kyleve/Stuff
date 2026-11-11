# StorageKit

A small, app-agnostic library for **containerized, mode-aware storage**. You ask
a `StorageSystem` for a container ("give me a container for this user id"), ask
that container for sub-containers ("…and one for logs"), and each container vends
the things you actually store — raw files, a namespaced key-value store, and a
SwiftData `ModelContainer` — all rooted in one directory it owns. A single `mode`
switch makes the whole tree persistent or in-memory, and two registration-based
teardown paths let you cleanly stop or delete any subtree.

StorageKit depends only on **Foundation + SwiftData** — no app code, no UI, and
not even `LifecycleKit` (wrap a teardown call in a `LifecycleStep` yourself if you
want one).

## What you get

- **A tree of containers.** A `StorageSystem` is the root (configuration + a
  vending point); every `StorageContainer` below it owns one directory and can
  vend child containers recursively. The on-disk layout mirrors the tree.
- **Storage lives on typed namespaces.** The container base type stays small;
  what you store hangs off `container.files` (raw file URLs), `container.keyValue`
  (a key-value store), and `container.swiftData` (isolated `ModelContainer`s), so
  each concern is separable and you can add your own namespace by extension.
- **Mode-aware vends.** In `.persistent` mode you get real files, a
  `UserDefaults` suite, and an on-disk SwiftData store; flip to `.inMemory` and
  the same calls give you a temp directory, an in-memory key-value store, and an
  `isStoredInMemoryOnly` SwiftData store with CloudKit forced off — **app and
  model code never has to know**.
- **Isolated SwiftData stores.** `swiftData.modelContainer(for:)` puts each store
  in its own child directory, so the `.store` file, its `-wal` / `-shm` sidecars,
  and any external-storage blobs stay together and delete together.
- **Idempotent, cached vends.** Asking for the same child container, key-value
  store, or model container twice returns the same instance (critical for
  `ModelContainer`, which must be unique per file).
- **Two teardown paths, never a boolean.** `deactivate()` reversibly releases
  handles but keeps data (account switch); `deleteContainer()` destroys a subtree
  for good (delete account). Both are children-first and registration-based, and
  deletion is **park-safe** (a failure before the point of no return leaves
  everything intact for a retry).

## Installation

`StorageKit` is a local SPM library in this repo (`Shared/StorageKit`). Add it to
a target's dependencies in [`Package.swift`](../../Package.swift):

```swift
.target(name: "YourCore", dependencies: [.target(name: "StorageKit")])
```

## Quick start

```swift
import StorageKit

// One system per app (or per test). Persistent in production…
let storage = try StorageSystem("Where", mode: .persistent(base: .applicationSupport()))
// …or ephemeral in tests/previews — nothing below changes:
// let storage = try StorageSystem("Where", mode: .inMemory)

let user = try await storage.container("user-1")     // a directory per user
let logs = try await user.container("logs")          // a subdirectory

// Raw file
let url = logs.files.url("today.json")
try Data(...).write(to: url)

// Key-value (a UserDefaults suite, or in-memory)
let prefs = await user.keyValue.store()
prefs.set(true, forKey: "onboarded")

// SwiftData (its store isolated in its own child directory)
let container = try await user.swiftData.modelContainer(for: [Note.self])
```

### Tearing down

```swift
// Switching accounts: release handles, keep everything on disk.
try await user.deactivate()        // re-vending later reactivates

// Deleting an account: destroy this user's whole subtree.
try await user.deleteContainer()   // siblings untouched

// Wipe the whole system (and its namespace directory).
try await storage.deleteAll()
```

## Public API

```swift
public enum StorageMode { case persistent(base: BaseDirectory), inMemory }

public struct BaseDirectory {
    public static func applicationSupport(subdirectory: String? = nil) -> BaseDirectory
    public static func caches(subdirectory: String? = nil) -> BaseDirectory
    public static func documents(subdirectory: String? = nil) -> BaseDirectory
    public static func library(subdirectory: String? = nil) -> BaseDirectory
    public static func custom(_ url: URL) -> BaseDirectory   // tests, relocations, App Group / security-scoped URLs
    public func resolvedURL(using: FileManager = .default) throws -> URL
}

public struct StorageKey: Hashable, Sendable, ExpressibleByStringLiteral {
    public init(_ raw: String)
    public init(_ key: some RawRepresentable<String>)
    public let name: String
}

public actor StorageSystem {
    public init(_ name: StorageKey, mode: StorageMode,
                fileManager: FileManager = .default) throws
    public nonisolated let mode: StorageMode
    public nonisolated let url: URL
    public func container(_ key: StorageKey) async throws -> StorageContainer
    public func deactivate() async throws
    public func deleteAll() async throws
}

public actor StorageContainer {
    public nonisolated let key: StorageKey
    public nonisolated let url: URL
    public nonisolated let mode: StorageMode

    public func container(_ key: StorageKey) async throws -> StorageContainer
    public func container(path keys: [StorageKey]) async throws -> StorageContainer

    // Storage namespaces (see below)
    public nonisolated var files: FileStorage
    public nonisolated var keyValue: KeyValueStorage
    public nonisolated var swiftData: SwiftDataStorage

    @discardableResult public func onDeactivate(_ handler: @escaping TeardownHandler) async -> Token
    @discardableResult public func prepareForDeletion(_ handler: @escaping TeardownHandler) async -> Token
    @discardableResult public func afterDeletion(_ handler: @escaping TeardownHandler) async -> Token
    public func deregister(_ token: Token) async

    public func deactivate() async throws
    public func deleteContainer() async throws
    public func deleteContents() async throws
}

// Storage namespaces — tiny Sendable facades vended by the accessors above.
public struct FileStorage: Sendable {
    public func url(_ name: String) -> URL
}
public struct KeyValueStorage: Sendable {
    public func store() async -> any KeyValueStore
}
public struct SwiftDataStorage: Sendable {
    public func modelContainer(for types: [any PersistentModel.Type],
                               named: StorageKey = "store",
                               cloudKit: CloudKitOption = .none) async throws -> ModelContainer
}

public protocol KeyValueStore: AnyObject, Sendable { /* typed bool/int/double/string/data */ }
public final class InMemoryKeyValueStore: KeyValueStore { public init() }
```

## How it works

- **Root vs. node.** `StorageSystem` is pure configuration (the `mode` — which
  carries the base directory in `.persistent` — plus an injected `FileManager`)
  and a vending point; it does no storage work beyond
  creating its namespace directory and delegating to a hidden root container. All
  operations live on `StorageContainer`. The split costs one extra directory level
  on disk, which is invisible to users.
- **Where things live.** Persistent systems root at `<base>/<name>`; in-memory
  systems root at a unique temporary directory removed by `deleteAll()`. A
  container's `url` is `<parent>/<key>`. A key-value store is a `UserDefaults`
  suite named hierarchically (e.g. `Where.user-1.logs`) — those live in the app's
  preferences, not the container directory, so deletion clears them explicitly.
- **Teardown order.** `deactivate()` runs `onDeactivate` handlers and drops cached
  vends across the subtree, children-first, leaving files in place;
  `deleteContainer()` runs, children-first: every `prepareForDeletion` handler
  (resources still live) → every `onDeactivate` handler (+ drop vends) → delete
  directories and key-value suites + deregister → every `afterDeletion` handler.
  Everything before the delete is reversible, so a throw there parks the operation
  with the subtree fully intact and a retry is safe; an `afterDeletion` throw is
  post-commit (the data is already gone, so it retries only that step — keep those
  handlers idempotent).

## Contracts & limitations

- **Vends are cached and idempotent**; the same key always returns the same
  instance until the node is deactivated (drops the cache) or deleted.
- **`StorageKey` sanitizes, it doesn't validate.** Path separators, `:`, and
  control characters become `_`, and empty / `.` / `..` get a leading `_`, so a
  key can't escape its directory — but two different raw strings can collapse to
  the same name, so keep keys distinct (prefer typed enums).
- **Errors surface.** Vending and teardown throw on real failures; nothing is
  swallowed into a benign default. Using a deleted container throws
  `StorageError.containerDeleted`.
- **`keyValue.store()` is intentionally non-throwing — don't `try`/`catch` it.**
  So reads stay terse (`store.bool(forKey:)`), it traps (rather than throws) when
  called on a container that's being deleted or already deleted. That's a
  *programmer error*, not a runtime condition to defend against on every access:
  hold the store through a live handle, and release it when you tear the container
  down (e.g. in an `onDeactivate` handler). The only way to hit the trap is to
  vend while a concurrent delete is in flight — a lifecycle bug to fix at the call
  site. If you need a throwing failure mode, use `container(_:)` /
  `swiftData.modelContainer(for:)` instead.
- **`files.url(_:)` is pure path construction.** It doesn't check the node's state
  or create the directory: on an `inactive` node the directory is absent until the
  next vend, and on a `deleted` one it's gone, so the URL points at a missing
  directory. Use it only while the container is live.
- **A model store is a child container named `named` (default `"store"`).** In
  `.persistent` mode it lives in the same key namespace as `container(_:)`, so
  don't also vend a plain child under that key — `container("store")` and the
  default model store would share one directory. Pass a distinct `named:` for
  each store, and avoid colliding child keys. Re-vending a store under the same
  name with a different `types` set throws `StorageError.modelStoreSchemaMismatch`.
- **CloudKit is a pass-through** (`.none` / `.automatic`), and is forced off in
  `.inMemory` mode. Richer CloudKit configuration is out of scope.
- **`deleteAll()` spends the system** — its namespace directory is gone
  afterwards; build a new `StorageSystem` to start over.

## Testing

Exercised with Swift Testing in a hosted bundle. Tests use
`.persistent(base: .custom(temp))` so they never touch the real Application
Support directory, and cover the tree,
both modes, cached/idempotent vends, key sanitization, key-value and SwiftData
vends, and — in detail — the two teardown paths: children-first ordering, the
`prepareForDeletion → onDeactivate → delete → afterDeletion` sequence, park-safe
retries on a thrown handler, and that deletion errors surface while leaving data
in place.
