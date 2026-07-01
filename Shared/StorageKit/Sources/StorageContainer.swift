import Foundation
import SwiftData

/// A handler registered for one of a container's teardown phases. Awaited during
/// `deactivate()` / `deleteContainer()`; a throw aborts the operation (see
/// `StorageContainer` for the park-safe guarantees).
public typealias TeardownHandler = @Sendable () async throws -> Void

/// A node in a `StorageSystem`'s tree, and the place where storage actually
/// happens. Each container owns one directory and vends child containers
/// (subdirectories) directly; the things you store inside it hang off typed
/// namespaces — ``files`` (raw file URLs), ``keyValue`` (a namespaced key-value
/// store), and ``swiftData`` (an isolated SwiftData `ModelContainer`). Children
/// are `StorageContainer`s too, so the tree is recursive below the root.
///
/// The base type stays deliberately small — lifecycle, the child registry, and
/// teardown — and each storage concern lives in its own namespace file
/// (`StorageContainer+Files`, `+KeyValue`, `+SwiftData`) that vends through a tiny
/// `Sendable` facade (`container.swiftData.modelContainer(for:)`). Add your own
/// namespace the same way: extend `StorageContainer` with a `nonisolated` accessor
/// returning a facade that composes the public primitives (child containers,
/// `files`, the teardown hooks).
///
/// An `actor`: it guards a mutable child registry and teardown registrations, and
/// serializes the file I/O behind vending and deletion. `key` / `url` / `mode`
/// are `nonisolated let` for cheap synchronous reads.
///
/// ## Deactivate vs. delete
///
/// Two registration-based, children-first teardown paths, never a boolean flag:
///
/// - ``deactivate()`` — reversible. Runs every `onDeactivate` handler and drops
///   the framework's own cached vends, but leaves files and registrations in
///   place; the node goes `inactive` and the next vend reactivates it. (account
///   switch / keep-data logout)
/// - ``deleteContainer()`` — irreversible. Runs, children-first across the
///   subtree: every `prepareForDeletion` handler (resources still live), then
///   every `onDeactivate` handler (+ drop cached vends), then deletes the
///   directories and key-value suites and deregisters, then every `afterDeletion`
///   handler. Everything before the delete is **park-safe** — a throw aborts with
///   nothing deleted, so a retry is safe; an `afterDeletion` throw is post-commit
///   (the data is already gone, so it retries only that step). The subtree is
///   marked `deleting` up front, so a vend racing the teardown is rejected rather
///   than resurrecting a directory mid-delete. (delete account / wipe-on-logout)
public actor StorageContainer {
    /// Lifecycle of a node, modeled as one enum (not loose flags) per the repo's
    /// "make invalid states unrepresentable" rule.
    enum State: Equatable {
        /// Live: the directory exists and vends work.
        case active
        /// `deactivate()`d: cached vends dropped and `onDeactivate` handlers run,
        /// but the directory and registrations remain. The next vend reactivates.
        case inactive
        /// `deleteContainer()` / `deleteContents()` is mid-flight on this subtree.
        /// Vends are rejected so a concurrent caller can't resurrect a directory
        /// that is being torn down. `wasActive` remembers the pre-freeze state so
        /// `onDeactivate` runs exactly once (skipped if the node was already
        /// `inactive`) and a parked (pre-commit) throw reverts to the right resting
        /// state (`active` or `inactive`); committing the delete advances it to
        /// `deleted`.
        case deleting(wasActive: Bool)
        /// `deleteContainer()`d: the directory is gone and the node is detached.
        /// Any further vend throws (or, for the non-throwing `keyValue.store()`,
        /// traps as the programmer error it is).
        case deleted
    }

    /// An opaque handle to a registered teardown handler. Returned by
    /// `onDeactivate` / `prepareForDeletion` / `afterDeletion` and passed back to
    /// `deregister(_:)`.
    public struct Token: Hashable, Sendable {
        fileprivate enum Phase {
            case onDeactivate
            case prepareForDeletion
            case afterDeletion
        }

        /// Identity of the container that issued the token. Per-node token ids
        /// start at 0, so without this a token from one container could match (and
        /// deregister) an unrelated handler on another. `deregister(_:)` ignores a
        /// token whose `node` isn't this container.
        fileprivate let node: ObjectIdentifier
        fileprivate let id: UInt64
        fileprivate let phase: Phase
    }

    /// A cached `ModelContainer` plus the identity of the model types it was built
    /// from, so a re-vend under the same store name with a different type set is
    /// caught instead of silently returning a container with the wrong schema.
    /// Internal (not `private`) so the `swiftData` namespace extension in a sibling
    /// file can build and read it.
    struct CachedModelStore {
        let container: ModelContainer
        let typeIDs: Set<ObjectIdentifier>
    }

    /// This node's key (a single, sanitized path component).
    public nonisolated let key: StorageKey
    /// This node's directory on disk.
    public nonisolated let url: URL
    /// Inherited from the owning `StorageSystem`.
    public nonisolated let mode: StorageMode

    /// Hierarchical suite-name for this node's `.persistent` key-value store, e.g.
    /// `"Where.<base-hash>.user-1.logs"`. The root segment folds in a hash of the
    /// system's resolved base directory (see `StorageSystem.rootSuiteName`) so
    /// distinct systems don't share a global suite; children append their keys.
    /// Unused in `.inMemory` mode.
    nonisolated let suiteName: String

    private weak var parent: StorageContainer?
    /// Internal (not `private`) so `@testable` tests can assert lifecycle
    /// transitions; only this type mutates it.
    private(set) var state: State = .active
    private var children: [StorageKey: StorageContainer] = [:]

    /// Cached vends. Internal (not `private`) so the `keyValue` / `swiftData`
    /// namespace extensions in sibling files can read and refresh them; only this
    /// type touches them, always under the actor. Dropped by teardown via
    /// `dropCachedVends()`.
    var keyValueStoreCache: (any KeyValueStore)?
    var modelContainerCache: [StorageKey: CachedModelStore] = [:]

    private var nextTokenID: UInt64 = 0
    private var onDeactivateHandlers: [UInt64: TeardownHandler] = [:]
    private var prepareForDeletionHandlers: [UInt64: TeardownHandler] = [:]
    private var afterDeletionHandlers: [UInt64: TeardownHandler] = [:]

    init(
        key: StorageKey,
        url: URL,
        mode: StorageMode,
        suiteName: String,
        parent: StorageContainer?,
    ) {
        self.key = key
        self.url = url
        self.mode = mode
        self.suiteName = suiteName
        self.parent = parent
    }

    // MARK: - Child containers

    /// Vend the child container named `childKey`, creating its directory the first
    /// time. Cached and idempotent: the same `childKey` always returns the same
    /// instance.
    public func container(_ childKey: StorageKey) throws -> StorageContainer {
        try activate()
        if let existing = children[childKey] {
            return existing
        }
        let childURL = url.appending(path: childKey.name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: childURL, withIntermediateDirectories: true)
        let child = StorageContainer(
            key: childKey,
            url: childURL,
            mode: mode,
            suiteName: "\(suiteName).\(childKey.name)",
            parent: self,
        )
        children[childKey] = child
        return child
    }

    /// Vend (creating as needed) the container at a path of nested keys, e.g.
    /// `container(path: ["user-1", "logs"])`.
    public func container(path keys: [StorageKey]) async throws -> StorageContainer {
        var node = self
        for childKey in keys {
            node = try await node.container(childKey)
        }
        return node
    }

    // MARK: - Teardown registration

    /// Register a handler run on **both** teardown paths: "stop using your handle
    /// and release it." Idempotent (it can run again after a parked retry). The
    /// returned `Token` deregisters it.
    @discardableResult
    public func onDeactivate(_ handler: @escaping TeardownHandler) -> Token {
        let id = takeTokenID()
        onDeactivateHandlers[id] = handler
        return Token(node: ObjectIdentifier(self), id: id, phase: .onDeactivate)
    }

    /// Register a handler run **only** on deletion, first, while resources are
    /// still live — reversible prep / final reads. A throw parks the deletion with
    /// nothing deleted, so don't commit irreversible external work here.
    @discardableResult
    public func prepareForDeletion(_ handler: @escaping TeardownHandler) -> Token {
        let id = takeTokenID()
        prepareForDeletionHandlers[id] = handler
        return Token(node: ObjectIdentifier(self), id: id, phase: .prepareForDeletion)
    }

    /// Register a handler run **only** on deletion, after the files are gone — the
    /// irreversible external commit ("it's gone now"). A throw leaves the deletion
    /// done and retries only this step, so handlers must be idempotent and must
    /// not assume the data still exists.
    @discardableResult
    public func afterDeletion(_ handler: @escaping TeardownHandler) -> Token {
        let id = takeTokenID()
        afterDeletionHandlers[id] = handler
        return Token(node: ObjectIdentifier(self), id: id, phase: .afterDeletion)
    }

    /// Remove a previously registered handler. A token issued by a different
    /// container is ignored (it identifies no handler here).
    public func deregister(_ token: Token) {
        guard token.node == ObjectIdentifier(self) else { return }
        switch token.phase {
            case .onDeactivate: onDeactivateHandlers[token.id] = nil
            case .prepareForDeletion: prepareForDeletionHandlers[token.id] = nil
            case .afterDeletion: afterDeletionHandlers[token.id] = nil
        }
    }

    // MARK: - Teardown

    /// Reversible teardown: run `onDeactivate` handlers and drop cached vends
    /// across the subtree, children-first, leaving files and registrations in
    /// place. A no-op on an already-inactive node. Re-vending reactivates.
    public func deactivate() async throws {
        guard state == .active else { return }
        for child in children.values {
            try await child.deactivate()
        }
        try await fireOnDeactivate()
        state = .inactive
    }

    /// Irreversible teardown of this container and its whole subtree. See the type
    /// doc for the phase order and the park-safe guarantee.
    public func deleteContainer() async throws {
        if state == .deleted {
            // Retry after a post-commit (`afterDeletion`) throw: the data is gone
            // and the node is already detached, so only the post-commit tail
            // remains to re-run.
            try await runAfterDeletion()
            releaseChildren()
            return
        }

        // Mark the whole subtree `deleting` first, so a vend racing the teardown
        // is rejected instead of recreating a directory we're about to remove.
        await beginDeleting()
        do {
            try await runPrepareForDeletion()
            try await runOnDeactivate()
            try removeDirectoryTree()
        } catch {
            // Park-safe: nothing is committed yet, so undo the freeze and leave
            // the subtree usable for a later retry.
            await revertDeleting()
            throw error
        }
        await purgeAndMarkDeleted()
        // Deregister from the parent as part of the commit, *before* the
        // post-commit step — so that even if an `afterDeletion` handler throws,
        // re-vending this key builds a fresh node instead of handing back this
        // deleted one. `runAfterDeletion` still recurses the (not-yet-released)
        // children, which are freed once it succeeds.
        await detachFromParent()
        try await runAfterDeletion()
        releaseChildren()
    }

    /// Delete every child container and clear this container's own files, but keep
    /// this (now empty) node live. The node's key-value suite is left intact.
    public func deleteContents() async throws {
        try activate()
        let existingChildren = Array(children.values)
        // Freeze this node while clearing it so a concurrent vend can't slip a new
        // child past the snapshot and have `clearLooseFiles()` delete it underfoot.
        // `activate()` above left it `active`, and the node itself survives, so the
        // `wasActive` payload is moot here.
        state = .deleting(wasActive: true)
        do {
            for child in existingChildren {
                try await child.deleteContainer()
            }
            try clearLooseFiles()
        } catch {
            state = .active
            throw error
        }
        state = .active
    }

    // MARK: - Internals

    private func takeTokenID() -> UInt64 {
        defer { nextTokenID += 1 }
        return nextTokenID
    }

    /// Ensure the node is live before a throwing vend, recreating the directory for
    /// an `inactive` node. Internal so the `swiftData` namespace extension can
    /// gate its vend on it. Throws `StorageError.containerDeleted` on a torn-down
    /// node.
    func activate() throws {
        switch state {
            case .active:
                break
            case .inactive:
                try FileManager.default.createDirectory(
                    at: url,
                    withIntermediateDirectories: true,
                )
                state = .active
            case .deleting, .deleted:
                throw StorageError.containerDeleted(key)
        }
    }

    /// Ensure the node is live enough to vend its **non-throwing** key-value store,
    /// reactivating an `inactive` node in place (the suite needs no directory, so
    /// this doesn't recreate one). Traps on a `deleting`/`deleted` node — see
    /// `KeyValueStorage.store()` for why that's a programmer error, not a throw.
    /// Internal so the `keyValue` namespace extension can gate its vend on it while
    /// the `state` setter stays private to this file.
    func requireLiveForKeyValueVend() {
        switch state {
            case .active:
                break
            case .inactive:
                state = .active
            case .deleting, .deleted:
                preconditionFailure(
                    "StorageKit: keyValue.store() on a deleted container \"\(key)\"",
                )
        }
    }

    private func dropCachedVends() {
        keyValueStoreCache = nil
        modelContainerCache.removeAll()
    }

    /// Run this node's `onDeactivate` handlers and drop its cached vends. Shared by
    /// the reversible `deactivate()` and the deletion path; neither touches state
    /// here so each can set its own (`inactive` vs. keep `deleting`).
    private func fireOnDeactivate() async throws {
        for handler in onDeactivateHandlers.values {
            try await handler()
        }
        dropCachedVends()
    }

    /// Mark the subtree `deleting` so vends are rejected for the duration of a
    /// teardown, recording each node's pre-freeze state in `wasActive`. Marks
    /// `self` before recursing: once `self` is `deleting` no new child can be
    /// vended onto it, so the child set it then snapshots is stable.
    private func beginDeleting() async {
        switch state {
            case .active:
                state = .deleting(wasActive: true)
            case .inactive:
                state = .deleting(wasActive: false)
            case .deleting, .deleted:
                return
        }
        for child in children.values {
            await child.beginDeleting()
        }
    }

    /// Undo `beginDeleting()` after a parked (pre-commit) throw, returning each
    /// still-intact node to the exact resting state it came from.
    private func revertDeleting() async {
        for child in children.values {
            await child.revertDeleting()
        }
        if case let .deleting(wasActive) = state {
            state = wasActive ? .active : .inactive
        }
    }

    /// The deletion-path counterpart to `deactivate()`: run `onDeactivate` +
    /// drop cached vends across the subtree, children-first, but keep the
    /// `deleting` state rather than going `inactive`. Skips a node that was
    /// already `inactive` before the delete, so its `onDeactivate` handlers (which
    /// ran during that earlier `deactivate()`) don't fire a second time.
    private func runOnDeactivate() async throws {
        for child in children.values {
            try await child.runOnDeactivate()
        }
        if case .deleting(wasActive: true) = state {
            try await fireOnDeactivate()
        }
    }

    private func runPrepareForDeletion() async throws {
        for child in children.values {
            try await child.runPrepareForDeletion()
        }
        for handler in prepareForDeletionHandlers.values {
            try await handler()
        }
    }

    private func removeDirectoryTree() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Children-first across the subtree: remove the (persistent) key-value suite,
    /// drop cached vends, and mark the node `deleted`. Disk directories are
    /// already gone via `removeDirectoryTree()`; suites live outside the directory
    /// so they're cleared here.
    private func purgeAndMarkDeleted() async {
        for child in children.values {
            await child.purgeAndMarkDeleted()
        }
        purgeKeyValueSuite()
        dropCachedVends()
        state = .deleted
    }

    private func purgeKeyValueSuite() {
        guard case .persistent = mode else { return }
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    private func runAfterDeletion() async throws {
        for child in children.values {
            try await child.runAfterDeletion()
        }
        for handler in afterDeletionHandlers.values {
            try await handler()
        }
    }

    private func detachFromParent() async {
        await parent?.removeChild(key)
        parent = nil
    }

    /// Release the subtree's child registry once `afterDeletion` has run. Kept
    /// separate from `detachFromParent()` so the post-commit step can still
    /// recurse the children before they're dropped.
    private func releaseChildren() {
        children.removeAll()
    }

    private func removeChild(_ childKey: StorageKey) {
        children[childKey] = nil
        // A model store lives in the child keyed by `childKey`, so its cached
        // `ModelContainer` is held here on the parent. Drop it when the child is
        // detached (e.g. by `deleteContents()` deleting that child) so a re-vend
        // rebuilds against fresh files instead of returning a container backed by
        // a just-deleted store.
        modelContainerCache[childKey] = nil
    }

    private func clearLooseFiles() throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
        )
        for item in contents {
            try FileManager.default.removeItem(at: item)
        }
    }
}
