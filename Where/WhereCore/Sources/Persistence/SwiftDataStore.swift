import Foundation
import PeriscopeCore
import RegionKit
import SwiftData

/// CloudKit-synced `WhereStore` backed by SwiftData. The `@Model` types are
/// kept `private`-ish (only the `@ModelActor`-isolated container sees them)
/// so callers never accidentally touch a SwiftData record outside the
/// actor's context.
///
/// Evidence blob bytes use `@Attribute(.externalStorage)` so CloudKit can
/// chunk them as `CKAsset`s.
///
/// Every `@Model` field is `Optional` with no placeholder default. SwiftData's
/// CloudKit mirror requires nullable or defaulted properties, and we picked
/// nullable so "field absent" is distinguishable from "field is a sentinel
/// value". `toValue()` is therefore allowed to return `nil` when a record is
/// missing mandatory state; readers `compactMap` and log a fault rather than
/// crashing on partial data.
///
/// ## Context strategy: main is read-only, writes use a per-`perform` peer
///
/// The actor's auto-generated `modelContext` (the "main" context) is
/// treated as **read-only**: every reader (`samples(in:)`,
/// `evidence(in:)`, ...) called outside a `perform { ... }` block
/// observes it, and any future SwiftUI `@Query` wired to the store
/// would observe it too.
///
/// Every outermost `perform` call spins up a fresh peer
/// `ModelContext(modelContainer)` and stashes it in `writerContext`
/// for the duration of the block. Mutating methods (`add(sample:)`,
/// `write(evidence:blob:)`, `setManualDay`, `clear(in:)`, and the
/// `EvidenceBlobStore` writers) trap if called outside a `perform`
/// body, and otherwise read/write through that peer. Reads issued
/// *inside* a `perform` also use the peer, so writes-within-the
/// transaction are visible to subsequent reads in the same block.
///
/// On outermost success the peer is `save()`d — that flushes the
/// batched writes to the persistent store, and the main context
/// picks the changes up on its next fetch. On outermost throw the
/// peer is discarded without saving, so a partial transaction
/// cleanly rolls back. Nested `perform` calls reuse the in-flight
/// peer so they coalesce into a single transaction.
///
/// ### Reentrancy & serialization
///
/// `perform`'s block is `async`, and this is an `actor`, so an `await`
/// inside the block suspends the actor and lets *other* jobs run
/// (actor reentrancy). "Am I nested?" therefore cannot be inferred
/// from `writerContext != nil`: a concurrent top-level `perform` on
/// another task would observe the in-flight peer, wrongly reuse it,
/// then trap in `mutationContext()` once the real owner cleared it.
///
/// So genuine nesting is detected via `activeTransactionStores`, a
/// task-local set of the store identities that currently hold a
/// transaction open *on this task's* call stack — task-locals don't
/// leak into unrelated concurrent tasks, so reentrancy can't
/// masquerade as nesting. And outermost transactions are serialized
/// through a reentrancy-safe async gate (`beginExclusive` /
/// `endExclusive`): only one peer is ever live at a time, so two
/// overlapping writers (e.g. the ingestor's passive stream and its
/// one-shot capture) queue instead of clobbering each other.
@ModelActor
public actor SwiftDataStore: WhereStore, EvidenceBlobStore {
    /// Backing storage for a `SwiftDataStore`. Callers choose explicitly so a
    /// developer build cannot accidentally validate local-only persistence
    /// while appearing to exercise CloudKit.
    public enum Storage: Sendable, Equatable {
        /// In-memory only. No disk, no CloudKit. Used by tests and previews.
        case inMemory
        /// On-disk SwiftData store with CloudKit sync disabled.
        case localOnly
        /// On-disk SwiftData store backed by the user's private
        /// CloudKit database.
        case cloudKit

        /// Whether a store of this mode can receive writes from outside this
        /// process — a sibling App Group process (the share extension) for any
        /// on-disk store, or a CloudKit sync from another device — surfaced as
        /// `.NSPersistentStoreRemoteChange`. In-memory stores have no shared
        /// container and no other writers, so there's nothing to observe.
        var observesRemoteChanges: Bool {
            switch self {
                case .inMemory: false
                case .localOnly, .cloudKit: true
            }
        }
    }

    /// App Group the on-disk store lives in, shared by the Where app, its
    /// widget extension, and the share extension so every process opens the
    /// *same* SwiftData store. Must match the `com.apple.security.application-groups`
    /// entitlement each of those targets declares (see `Project.swift`).
    public static let appGroupIdentifier = "group.com.stuff.where"

    public static func makeContainer(storage: Storage) throws -> ModelContainer {
        // A plain `Schema` of the live models. SwiftData runs implicit
        // lightweight migration when the on-disk store predates an additive
        // change (new optional fields, new models); the launch flow shows
        // migration UI purely off slowness, not a predicted version, so no
        // `VersionedSchema`/`SchemaMigrationPlan` scaffolding is needed.
        let schema = Schema(inspectorModelTypes)
        let configuration = modelConfiguration(storage: storage, schema: schema)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// The exact store URL used inside the resolved App Group container.
    /// Inspector passes the entitlement-resolved root so this lookup never asks
    /// SwiftData to resolve an unavailable App Group in a test host.
    public static func inspectorStoreURL(groupContainerURL: URL) -> URL {
        groupContainerURL.appending(
            path: "Library/Application Support/default.store",
            directoryHint: .notDirectory,
        )
    }

    private static func modelConfiguration(
        storage: Storage,
        schema: Schema,
    ) -> ModelConfiguration {
        // On-disk storage lives in the App Group container so the share
        // extension (and any other sibling process) writes into the same store
        // the app reads. An in-memory store has no container — leave it default.
        let groupContainer: ModelConfiguration.GroupContainer = switch storage {
            case .inMemory: .none
            case .localOnly, .cloudKit: .identifier(appGroupIdentifier)
        }
        // CloudKit mode backs the container with `NSPersistentCloudKitContainer`,
        // which enables persistent-history tracking and posts
        // `.NSPersistentStoreRemoteChange` on remote import — no extra knobs
        // needed (and SwiftData exposes none). `make` observes that notification
        // via `PersistentStoreRemoteChangeSource`.
        return ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: storage == .inMemory,
            groupContainer: groupContainer,
            cloudKitDatabase: storage == .cloudKit ? .automatic : .none,
        )
    }

    /// Convenience for tests and SwiftUI previews: builds an
    /// `.inMemory` container and wraps it in a `SwiftDataStore`. Each
    /// call returns an independent store with its own backing
    /// container, so callers get a clean slate per use without any
    /// shared state to reset.
    public static func inMemory() throws -> SwiftDataStore {
        let container = try makeContainer(storage: .inMemory)
        return SwiftDataStore(modelContainer: container)
    }

    /// App-wiring factory: builds a store for the explicitly selected storage
    /// mode and wraps it in a `SwiftDataStore`. The `@ModelActor`-generated
    /// `init(modelContainer:)` is not reachable from other modules, so
    /// this is the supported entry point for opening a store.
    ///
    /// Each process opens its on-disk store **once** and injects it where
    /// it's needed — in the app, the launch's `resolve-scope` step opens it
    /// (only once the user has committed to using the app for real) and
    /// the App Intents stack shares it via
    /// `WhereServices.forIntents(sharingStoreOf:)` — rather than a second
    /// caller opening another container over the same file (two containers
    /// racing to *create* the store on a fresh install is how the launch
    /// once failed with `SwiftDataError`).
    public static func make(storage: Storage) throws -> SwiftDataStore {
        let container = try logger.measure(.open) { try makeContainer(storage: storage) }
        if storage == .inMemory {
            logger { .openedInMemory(mode: String(describing: storage)) }
        } else {
            // Log the resolved on-disk path and whether the App Group container
            // is actually reachable at runtime. If the App Group capability isn't
            // provisioned for the signing in use, `containerURL(...)` is nil and
            // SwiftData falls back to the per-process sandbox — which reads as
            // "my old data is still here / the store didn't move" rather than an
            // error. Logging both makes that diagnosable instead of a guess.
            let groupResolved = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) != nil
            let url = container.configurations.first?.url.path(percentEncoded: false) ?? "unknown"
            logger {
                .openedOnDisk(
                    mode: String(describing: storage),
                    appGroupResolved: groupResolved,
                    url: url,
                )
            }
        }
        let store = SwiftDataStore(modelContainer: container)
        // On-disk stores live in a shared App Group container, so another process
        // (the share extension) — or, for CloudKit, a sync from another device —
        // can commit behind our back. Both surface as
        // `.NSPersistentStoreRemoteChange` (persistent-history tracking is on for
        // on-disk stores). Core Data posts that notification for local saves as
        // well, so the source filters history by this store instance's author
        // before forwarding only external writes into `changes()`. This makes a
        // share-extension add show up live in the running app (debug included),
        // not just on next launch.
        if storage.observesRemoteChanges {
            if let storeURL = container.configurations.first?.url {
                try store.startObservingRemoteChanges(PersistentStoreRemoteChangeSource(
                    modelContainer: container,
                    storeURL: storeURL,
                    localTransactionAuthor: store.localTransactionAuthor,
                    center: .default,
                ))
            } else {
                assertionFailure("An on-disk Where store must have a resolved URL")
            }
        }
        return store
    }

    #if DEBUG
        /// Test seam: an `.inMemory` store wired to drive its `changes()`
        /// fan-out from `remoteChangeSource`, so the remote-import path is
        /// exercisable without CloudKit or a device. The production equivalent
        /// is `make(storage: .cloudKit)`, which wires a
        /// `PersistentStoreRemoteChangeSource`. `@_spi(Testing)` (per the
        /// agents.md) so the remote-change wiring stays folded into a factory —
        /// there's no public `startObservingRemoteChanges` to call twice.
        @_spi(Testing)
        public static func inMemory(
            remoteChangeSource: ScriptedStoreRemoteChangeSource,
        ) throws -> SwiftDataStore {
            let container = try makeContainer(storage: .inMemory)
            return inMemory(
                modelContainer: container,
                remoteChangeSource: remoteChangeSource,
            )
        }

        /// Variant that exposes the shared container to persistence-boundary
        /// tests, allowing them to commit a same-epoch external write before
        /// driving the corresponding remote-change notification.
        @_spi(Testing)
        public static func inMemory(
            modelContainer: ModelContainer,
            remoteChangeSource: ScriptedStoreRemoteChangeSource,
        ) -> SwiftDataStore {
            let store = SwiftDataStore(modelContainer: modelContainer)
            store.startObservingRemoteChanges(remoteChangeSource)
            return store
        }

    #endif

    /// The live `@Model` record types, erased to existentials so a generic
    /// Inspector runtime can enumerate them without naming the (intentionally
    /// internal) record types. Mirrors the `Schema` in `makeContainer`.
    public static var inspectorModelTypes: [any PersistentModel.Type] {
        [
            SDWhereDataEpoch.self,
            SDBackupImportReceipt.self,
            SDLocationSample.self,
            SDEvidence.self,
            SDManualDay.self,
            SDDismissedIssue.self,
            SDTrackedRegion.self,
            SDRecordingDeviceProfile.self,
            SDRecordingDeviceMetadataChange.self,
            SDRecordingDeviceCheckIn.self,
            SDRecordingAssignmentChange.self,
            SDRecordingDeviceArchive.self,
        ]
    }

    private static let logger = WhereLog.root(SwiftDataStoreLog.self)
    /// Process/store-instance author stamped on every local write. A sibling
    /// process opens a distinct store instance and therefore gets a distinct
    /// value, allowing persistent history to distinguish its commits from ours.
    private nonisolated let localTransactionAuthor = "where-\(UUID().uuidString)"

    /// Fans "committed data changed" pings to `changes()` subscribers. Fired
    /// once per outermost `perform` commit (see `perform`).
    private let changeBroadcaster = StoreChangeBroadcaster()
    private let remoteChangeBroadcaster = StoreChangeBroadcaster()

    /// A fresh stream that pings whenever committed data changes (see the
    /// `WhereStore` contract). `nonisolated` so a subscriber needn't hop onto
    /// the actor just to subscribe — the broadcaster is an immutable, `Sendable`
    /// `let`, and `subscribe()` is itself thread-safe.
    public nonisolated func changes() -> AsyncStream<Void> {
        changeBroadcaster.subscribe()
    }

    public nonisolated func remoteChanges() -> AsyncStream<Void> {
        remoteChangeBroadcaster.subscribe()
    }

    /// Forwards a `StoreRemoteChangeSource`'s remote-import events into the same
    /// `changes()` fan-out a local commit pings. `nonisolated(unsafe)` for the
    /// same reason as the scanner's: assigned once during setup, cancelled in
    /// `deinit`, never accessed concurrently.
    private nonisolated(unsafe) var remoteChangeTask: Task<Void, Never>?

    /// Begin re-pinging `changes()` on every remote import from `source`, so a
    /// CloudKit sync from another device refreshes observers identically to a
    /// local write — one read path for every write origin. `nonisolated` so the
    /// factories can wire it without hopping onto the actor. The forwarding task
    /// retains `source`, so the caller needn't.
    ///
    /// `private` and wired exactly once per store from a factory — `make`
    /// (any on-disk store) or `inMemory(remoteChangeSource:)` (tests) — so
    /// there's deliberately no way to call it twice. That keeps the
    /// unsynchronized, `nonisolated(unsafe)` `remoteChangeTask` sound without a
    /// re-arm/cancel dance: it's assigned once before the store is shared and
    /// only read again in `deinit`.
    private nonisolated func startObservingRemoteChanges(_ source: any StoreRemoteChangeSource) {
        remoteChangeTask = Task { [changeBroadcaster, remoteChangeBroadcaster] in
            for await _ in source.remoteChanges {
                changeBroadcaster.send()
                remoteChangeBroadcaster.send()
            }
        }
    }

    deinit {
        remoteChangeTask?.cancel()
        changeBroadcaster.finishAll()
        remoteChangeBroadcaster.finishAll()
    }

    /// Peer `ModelContext` active for the duration of an outermost
    /// `perform { ... }` block. `nil` outside `perform`. See the
    /// type doc for the full context-strategy explanation.
    private var writerContext: ModelContext?
    /// Logical generation every write in the active transaction belongs to, plus the real
    /// maximal heads a rotation must join when the write id is a synthetic reset conflict.
    /// Cached once per outer transaction so a large backup import does not refetch the tiny epoch
    /// ledger for every row; ``rotateDataEpoch(reason:changedBy:at:)`` replaces it in-place.
    private var writerEpoch: WhereDataEpoch.Resolution?
    /// Dedicated read context and epoch active for one multi-table snapshot. Reads inside the
    /// snapshot use this pair even if CloudKit imports a newer generation mid-block; the block
    /// then fails its end validation rather than returning mixed-generation state.
    private var snapshotContext: ModelContext?
    private var snapshotEpoch: WhereDataEpoch?

    /// The store identities that currently have an outermost `perform`
    /// transaction open *on the current task's* call stack. A `perform` whose
    /// store id is already present is a genuine lexical nested call and reuses
    /// the in-flight peer; a call without it (e.g. a concurrent writer on
    /// another task) is a new outermost transaction. Task-local so reentrancy
    /// on a *different* task can't be mistaken for nesting — see the type doc.
    @TaskLocal private static var activeTransactionStores: Set<ObjectIdentifier> = []
    @TaskLocal private static var activeSnapshotStores: Set<ObjectIdentifier> = []

    /// Whether an outermost transaction is currently live. Guards the
    /// serialization gate below.
    private var isTransacting = false

    /// Tasks parked in `beginExclusive` waiting for the live transaction to
    /// finish, resumed FIFO by `endExclusive`.
    private var transactionWaiters: [CheckedContinuation<Void, Never>] = []

    /// Acquire exclusive ownership of the transaction slot, suspending until any
    /// in-flight outermost `perform` completes. Reentrancy-safe: the
    /// `isTransacting` check and the waiter enqueue happen without an
    /// intervening `await`, so a releasing `endExclusive` can't slip between
    /// them and drop the wakeup. Ownership is handed directly to a woken waiter
    /// (see `endExclusive`), so on resume it already owns the slot — no re-check
    /// and no re-enqueue.
    private func beginExclusive() async {
        if isTransacting {
            await withCheckedContinuation { transactionWaiters.append($0) }
        } else {
            isTransacting = true
        }
    }

    /// Release the transaction slot. With a waiter queued, ownership is handed
    /// directly to the next one in FIFO order — `isTransacting` stays `true` so
    /// no fresh caller can slip in ahead of it; otherwise the slot goes idle.
    private func endExclusive() {
        if transactionWaiters.isEmpty {
            isTransacting = false
        } else {
            transactionWaiters.removeFirst().resume()
        }
    }

    public func perform<T: Sendable>(
        _ block: @Sendable () async throws -> T,
    ) async throws -> T {
        try await perform(sendsChange: true, expectedDataEpochID: nil, block)
    }

    public func perform<T: Sendable>(
        expectedDataEpochID: WhereDataEpochID,
        _ block: @Sendable () async throws -> T,
    ) async throws -> T {
        try await perform(
            sendsChange: true,
            expectedDataEpochID: expectedDataEpochID,
            block,
        )
    }

    public func readSnapshot<T: Sendable>(
        _ block: @Sendable () async throws -> T,
    ) async throws -> T {
        let storeID = ObjectIdentifier(self)
        if Self.activeSnapshotStores.contains(storeID)
            || Self.activeTransactionStores.contains(storeID)
        {
            return try await block()
        }

        await beginExclusive()
        let peer = ModelContext(modelContainer)
        snapshotContext = peer
        defer {
            snapshotEpoch = nil
            snapshotContext = nil
            endExclusive()
        }
        // A persistent-store transaction becomes fetch-visible atomically with
        // its history row, but Core Data is allowed to post the corresponding
        // remote-change notification later. Bracket every table fetch with the
        // history head from this same peer context: if an external transaction
        // lands anywhere across the block, its monotonically increasing id
        // changes and the assembled value is rejected. Our own `perform`s are
        // held behind `beginExclusive`, so a crossing commit can only come from
        // another process or CloudKit.
        let startingHistoryTransactionID = try Self.latestHistoryTransactionID(in: peer)
        let epoch = try Self.resolvedDataEpoch(in: peer)
        snapshotEpoch = epoch
        let result = try await Self.$activeSnapshotStores.withValue(
            Self.activeSnapshotStores.union([storeID]),
        ) {
            try await block()
        }
        guard try Self.latestHistoryTransactionID(in: peer) == startingHistoryTransactionID else {
            throw RecordingPersistenceError.dataEpochChanged
        }
        let current = try Self.resolvedDataEpoch(in: ModelContext(modelContainer))
        guard current.id == epoch.id else {
            throw RecordingPersistenceError.dataEpochChanged
        }
        return result
    }

    /// The durable store generation used to bracket a multi-table read. Unlike
    /// `.NSPersistentStoreRemoteChange`, persistent history is committed in the
    /// same transaction as the rows it describes, so it cannot lag visibility.
    private static func latestHistoryTransactionID(in context: ModelContext) throws -> Int64 {
        var descriptor = HistoryDescriptor<DefaultHistoryTransaction>(
            sortBy: [SortDescriptor(\.transactionIdentifier, order: .reverse)],
        )
        descriptor.fetchLimit = 1
        return try context.fetchHistory(descriptor).first?.transactionIdentifier ?? .min
    }

    #if DEBUG
        /// Test seam for the data half of a remote import: commit recording
        /// values without emitting the local-write `changes()` ping. Tests pair
        /// this with `ScriptedStoreRemoteChangeSource.yield()` so observers can
        /// only refresh through the production remote-import path.
        @_spi(Testing)
        public func simulateRemoteRecordingImport(
            profiles: [RecordingDeviceProfile],
            metadataChanges: [RecordingDeviceMetadataChange],
            checkIns: [RecordingDeviceCheckIn],
            assignmentChanges: [RecordingAssignmentChange],
            archives: [RecordingDeviceArchive],
        ) async throws {
            try await perform(sendsChange: false, expectedDataEpochID: nil) {
                for profile in profiles {
                    try await self.addRecordingDeviceProfile(profile)
                }
                for metadataChange in metadataChanges {
                    try await self.addRecordingDeviceMetadataChange(metadataChange)
                }
                for checkIn in checkIns {
                    try await self.setRecordingDeviceCheckIn(checkIn)
                }
                for assignmentChange in assignmentChanges {
                    try await self.addRecordingAssignmentChange(assignmentChange)
                }
                for archive in archives {
                    try await self.addRecordingDeviceArchive(archive)
                }
            }
        }

        /// Test seam for remote day data, paired with
        /// `ScriptedStoreRemoteChangeSource.yield()` just like the recording import seam above.
        @_spi(Testing)
        public func simulateRemoteDayImport(
            samples: [LocationSample],
            manualDays: [DayPresence],
        ) async throws {
            try await perform(sendsChange: false, expectedDataEpochID: nil) {
                for sample in samples {
                    try await self.add(sample: sample)
                }
                for manualDay in manualDays {
                    try await self.setManualDay(manualDay)
                }
            }
        }
    #endif

    private func perform<T: Sendable>(
        sendsChange: Bool,
        expectedDataEpochID: WhereDataEpochID?,
        _ block: @Sendable () async throws -> T,
    ) async throws -> T {
        precondition(
            !Self.activeSnapshotStores.contains(ObjectIdentifier(self)),
            "A read snapshot cannot start a store mutation.",
        )
        // Genuine nested call on this task: a write transaction is already in
        // flight for this store. Reuse its peer so nested writes coalesce into
        // the same save / discard decision; only the outermost perform decides
        // commit vs. rollback. (Task-local, so a concurrent perform on another
        // task doesn't take this branch — see the type doc.)
        if Self.activeTransactionStores.contains(ObjectIdentifier(self)) {
            if let expectedDataEpochID, writerEpoch?.current.id != expectedDataEpochID {
                throw RecordingPersistenceError.dataEpochChanged
            }
            return try await block()
        }
        // Outermost call: serialize against any other in-flight transaction so
        // overlapping top-level writers can't clobber `writerContext` through
        // actor reentrancy.
        await beginExclusive()
        let peer = ModelContext(modelContainer)
        peer.author = localTransactionAuthor
        writerContext = peer
        defer {
            writerEpoch = nil
            writerContext = nil
            endExclusive()
        }
        writerEpoch = try Self.resolvedDataEpochResolution(in: peer)
        if let expectedDataEpochID, writerEpoch?.current.id != expectedDataEpochID {
            throw RecordingPersistenceError.dataEpochChanged
        }
        // One span per committed transaction, opened *after* the exclusivity
        // wait so it measures the write rather than the queueing behind another
        // writer. Only the outermost `perform` spans, so a nested write doesn't
        // nest a duplicate inside its own commit.
        return try await Self.logger.measure(.commit) {
            // Mark this store as transacting for the duration of the block so
            // nested `perform` calls on this task reuse the peer above.
            let result = try await Self.$activeTransactionStores.withValue(
                Self.activeTransactionStores.union([ObjectIdentifier(self)]),
            ) {
                try await block()
            }
            // Outermost success: save the peer, which propagates the batched
            // writes to the persistent store. The main `modelContext` picks the
            // changes up on its next fetch. A throw before here (from the block
            // or the save) skips the save, so the peer is discarded without
            // reaching the persistent store — a clean rollback of the entire
            // transaction — while `defer` still clears `writerContext` and
            // releases the gate.
            try peer.save()
            // The persistent store can import a CloudKit reset while this
            // asynchronous transaction body is suspended. Saving old-epoch
            // rows is harmless (they are inert), but reporting success would
            // let callers run post-commit side effects under stale authority.
            // Re-resolve through a fresh context after the commit and fail the
            // operation if its transaction epoch lost before returning.
            guard let committedEpochID = writerEpoch?.current.id else {
                preconditionFailure("A store transaction must retain its data epoch through save.")
            }
            let currentEpoch = try Self.resolvedDataEpoch(in: ModelContext(modelContainer))
            guard currentEpoch.id == committedEpochID else {
                throw RecordingPersistenceError.dataEpochChanged
            }
            // Committed: ping `changes()` subscribers so they re-read. Only the
            // outermost `perform` reaches here (nested calls returned above
            // without saving), so a transaction pings exactly once. The DEBUG
            // remote-import seam suppresses this local ping; its scripted
            // source emits the corresponding remote one separately.
            if sendsChange {
                changeBroadcaster.send()
            }
            return result
        }
    }

    /// The context mutating methods write to. Mutations are
    /// contract-required to run inside `perform { ... }`; calling
    /// them outside is a programmer error and traps so the broken
    /// contract surfaces immediately instead of silently no-op'ing
    /// the save.
    private func mutationContext() -> ModelContext {
        guard let writerContext else {
            preconditionFailure(
                "SwiftDataStore mutations must be called inside store.perform { ... }",
            )
        }
        return writerContext
    }

    /// The context read methods fetch from. Inside `perform`, reads
    /// use the in-flight peer so writes-within-the-transaction are
    /// visible to subsequent reads in the same block. Outside, reads
    /// observe the main `modelContext` (committed state only).
    private func readContext() -> ModelContext {
        let storeID = ObjectIdentifier(self)
        if Self.activeTransactionStores.contains(storeID) {
            guard let writerContext else {
                preconditionFailure("An active store transaction must own a writer context.")
            }
            return writerContext
        }
        if Self.activeSnapshotStores.contains(storeID) {
            guard let snapshotContext else {
                preconditionFailure("An active store snapshot must own a read context.")
            }
            return snapshotContext
        }
        return modelContext
    }

    public func dataEpoch() async throws -> WhereDataEpoch {
        if Self.activeTransactionStores.contains(ObjectIdentifier(self)), let writerEpoch {
            return writerEpoch.current
        }
        if Self.activeSnapshotStores.contains(ObjectIdentifier(self)), let snapshotEpoch {
            return snapshotEpoch
        }
        return try Self.resolvedDataEpoch(in: readContext())
    }

    public func rotateDataEpoch(
        reason: WhereDataEpochReason,
        changedBy deviceID: RecordingDeviceID,
        at date: Date,
    ) async throws -> WhereDataEpoch {
        precondition(reason.isDestructive, "Only a destructive operation rotates the data epoch.")
        let context = mutationContext()
        guard let resolution = writerEpoch else {
            preconditionFailure("A store transaction must resolve its data epoch before mutation.")
        }
        let current = resolution.current
        let history = try Self.dataEpochHistory(in: context)
        let refreshedResolution = try WhereDataEpoch.resolve(in: history)
        guard refreshedResolution.current.id == current.id else {
            throw RecordingPersistenceError.dataEpochChanged
        }
        let heads = refreshedResolution.realHeads

        // Remove only the logical state being replaced. Older generations may still be present
        // because CloudKit is eventually consistent; they remain inert, and deleting them is an
        // opportunistic storage cleanup rather than the correctness boundary.
        try Self.deleteRows(in: context, belongingTo: current.id)

        // One semantic destructive operation causally joins every observed real head. Resolve
        // this single persisted node before any following write asks `mutationEpochID()` for its
        // scope; a synthetic reset-conflict id is never stored as a parent.
        let changedAt = heads.reduce(date) { partialResult, head in
            max(partialResult, head.changedAt)
        }
        guard let maximumRevision = heads.map(\.revision).max() else {
            preconditionFailure("The implicit data epoch must always be a real causal head.")
        }
        let (revision, overflow) = maximumRevision.addingReportingOverflow(1)
        guard !overflow else {
            throw RecordingPersistenceError.dataEpochRevisionExhausted
        }
        let next = WhereDataEpoch(
            id: WhereDataEpochID(rawValue: UUID()),
            parentIDs: heads.map(\.id),
            revision: revision,
            changedAt: changedAt,
            changedByDeviceID: deviceID,
            reason: reason,
        )
        context.insert(SDWhereDataEpoch(value: next))
        let nextResolution = try WhereDataEpoch.resolve(in: history + [next])
        guard nextResolution.current == next, nextResolution.realHeads == [next] else {
            preconditionFailure("A complete epoch join must resolve to its new persisted node.")
        }
        writerEpoch = nextResolution
        return next
    }

    public func backupImportReceipt(
        id: UUID,
        installationID: RecordingDeviceID,
    ) async throws -> BackupImportReceipt? {
        let installationID = installationID.rawValue
        let records = try readContext().fetch(FetchDescriptor<SDBackupImportReceipt>(
            predicate: #Predicate {
                $0.id == id && $0.installationID == installationID
            },
        ))
        guard records.count <= 1 else {
            Self.logImmutableConflict(
                type: String(describing: BackupImportReceipt.self),
                id: id.uuidString,
                count: records.count,
            )
            throw RecordingPersistenceError.conflictingImmutableRecord(id: id)
        }
        guard let record = records.first else { return nil }
        guard let value = record.toValue() else {
            Self.logFault(forCorrupt: record)
            throw RecordingPersistenceError.conflictingImmutableRecord(id: id)
        }
        return value
    }

    public func addBackupImportReceipt(
        id: UUID,
        installationID: RecordingDeviceID,
    ) async throws {
        let context = mutationContext()
        let receipt = BackupImportReceipt(
            id: id,
            installationID: installationID,
            dataEpochID: mutationEpochID(),
        )
        let records = try context.fetch(FetchDescriptor<SDBackupImportReceipt>(
            predicate: #Predicate { $0.id == id },
        ))
        if records.isEmpty {
            context.insert(SDBackupImportReceipt(value: receipt))
            return
        }
        guard records.count == 1, records.first?.toValue() == receipt else {
            Self.logImmutableConflict(
                type: String(describing: BackupImportReceipt.self),
                id: id.uuidString,
                count: records.count,
            )
            throw RecordingPersistenceError.conflictingImmutableRecord(id: id)
        }
    }

    public func removeBackupImportReceipt(
        id: UUID,
        installationID: RecordingDeviceID,
    ) async throws {
        let context = mutationContext()
        let installationID = installationID.rawValue
        for record in try context.fetch(FetchDescriptor<SDBackupImportReceipt>(
            predicate: #Predicate {
                $0.id == id && $0.installationID == installationID
            },
        )) {
            context.delete(record)
        }
    }

    private static func dataEpochHistory(in context: ModelContext) throws -> [WhereDataEpoch] {
        var descriptor = FetchDescriptor<SDWhereDataEpoch>(
            sortBy: [SortDescriptor(\.revision), SortDescriptor(\.id)],
        )
        descriptor.includePendingChanges = true
        let records = try context.fetch(descriptor)
        var values: [WhereDataEpoch] = []
        for record in records {
            guard let value = record.toValue() else {
                logFault(forCorrupt: record)
                throw RecordingPersistenceError.incompleteDataEpochHistory
            }
            values.append(value)
        }
        var canonical: [WhereDataEpoch] = []
        for (id, duplicates) in Dictionary(grouping: values, by: \.id) {
            guard Set(duplicates).count == 1 else {
                logImmutableConflict(
                    type: String(describing: WhereDataEpoch.self),
                    id: id.rawValue.uuidString,
                    count: duplicates.count,
                )
                throw RecordingPersistenceError.conflictingImmutableRecord(id: id.rawValue)
            }
            if let value = duplicates.first { canonical.append(value) }
        }
        return canonical
    }

    private static func resolvedDataEpochResolution(
        in context: ModelContext,
    ) throws -> WhereDataEpoch.Resolution {
        try WhereDataEpoch.resolve(in: dataEpochHistory(in: context))
    }

    private static func resolvedDataEpoch(in context: ModelContext) throws -> WhereDataEpoch {
        try resolvedDataEpochResolution(in: context).current
    }

    private func mutationEpochID() -> WhereDataEpochID {
        guard let writerEpoch else {
            preconditionFailure("SwiftDataStore mutations require an active data epoch.")
        }
        return writerEpoch.current.id
    }

    private func readEpochID(in context: ModelContext) throws -> WhereDataEpochID {
        if Self.activeTransactionStores.contains(ObjectIdentifier(self)), let writerEpoch {
            return writerEpoch.current.id
        }
        if Self.activeSnapshotStores.contains(ObjectIdentifier(self)), let snapshotEpoch {
            return snapshotEpoch.id
        }
        return try Self.resolvedDataEpoch(in: context).id
    }

    private static func belongs(_ storedEpochID: UUID?, to epochID: WhereDataEpochID) -> Bool {
        WhereDataEpochID(rawValue: storedEpochID ?? WhereDataEpochID.initial.rawValue) == epochID
    }

    private static func deleteRows(
        in context: ModelContext,
        belongingTo epochID: WhereDataEpochID,
    ) throws {
        for record in try context.fetch(FetchDescriptor<SDLocationSample>())
            where belongs(record.epochID, to: epochID)
        {
            context.delete(record)
        }
        for record in try context.fetch(FetchDescriptor<SDEvidence>())
            where belongs(record.epochID, to: epochID)
        {
            context.delete(record)
        }
        for record in try context.fetch(FetchDescriptor<SDManualDay>())
            where belongs(record.epochID, to: epochID)
        {
            context.delete(record)
        }
        for record in try context.fetch(FetchDescriptor<SDDismissedIssue>())
            where belongs(record.epochID, to: epochID)
        {
            context.delete(record)
        }
        for record in try context.fetch(FetchDescriptor<SDTrackedRegion>())
            where belongs(record.epochID, to: epochID)
        {
            context.delete(record)
        }
        for record in try context.fetch(FetchDescriptor<SDRecordingDeviceMetadataChange>())
            where belongs(record.epochID, to: epochID)
        {
            context.delete(record)
        }
        for record in try context.fetch(FetchDescriptor<SDRecordingDeviceCheckIn>())
            where belongs(record.epochID, to: epochID)
        {
            context.delete(record)
        }
        for record in try context.fetch(FetchDescriptor<SDRecordingAssignmentChange>())
            where belongs(record.epochID, to: epochID)
        {
            context.delete(record)
        }
        for record in try context.fetch(FetchDescriptor<SDRecordingDeviceArchive>())
            where belongs(record.epochID, to: epochID)
        {
            context.delete(record)
        }
    }

    public func add(sample: LocationSample) async throws {
        let context = mutationContext()
        let epochID = mutationEpochID()
        let id = sample.id
        let existing = try context.fetch(
            FetchDescriptor<SDLocationSample>(predicate: #Predicate { $0.id == id }),
        )
        let active = existing.filter { Self.belongs($0.epochID, to: epochID) }
        if let canonical = active.first {
            canonical.update(from: sample, epochID: epochID)
            for duplicate in active.dropFirst() {
                context.delete(duplicate)
            }
        } else {
            context.insert(SDLocationSample(value: sample, epochID: epochID))
        }
    }

    public func samples(in interval: DateInterval) async throws -> [LocationSample] {
        let context = readContext()
        let epochID = try readEpochID(in: context)
        let start = interval.start
        let end = interval.end
        var descriptor = FetchDescriptor<SDLocationSample>(
            predicate: #Predicate {
                if let timestamp = $0.timestamp {
                    timestamp >= start && timestamp < end
                } else {
                    false
                }
            },
            sortBy: [SortDescriptor(\.timestamp)],
        )
        descriptor.includePendingChanges = true
        // Spanning the fetch *and* the materialization together is deliberate:
        // decoding a year of rows into values is a real share of the cost, and
        // splitting them would only obscure it.
        return try Self.logger.measure(.fetchSamples) {
            try context.fetch(descriptor).compactMap { record in
                guard Self.belongs(record.epochID, to: epochID) else { return nil }
                let value = record.toValue()
                if value == nil { Self.logFault(forCorrupt: record) }
                return value
            }
        }
    }

    public func allSamples() async throws -> [LocationSample] {
        let context = readContext()
        let epochID = try readEpochID(in: context)
        var descriptor = FetchDescriptor<SDLocationSample>(sortBy: [SortDescriptor(\.timestamp)])
        descriptor.includePendingChanges = true
        return try context.fetch(descriptor).compactMap { record in
            guard Self.belongs(record.epochID, to: epochID) else { return nil }
            let value = record.toValue()
            if value == nil { Self.logFault(forCorrupt: record) }
            return value
        }
    }

    // MARK: - Recording devices

    public func recordingDevices() async throws -> [RecordingDevice] {
        async let profiles = recordingDeviceProfiles()
        async let metadataChanges = recordingDeviceMetadataChanges()
        async let checkIns = recordingDeviceCheckIns()
        async let archives = recordingDeviceArchives()
        let (resolvedProfiles, resolvedMetadata, resolvedCheckIns, resolvedArchives) = try await (
            profiles,
            metadataChanges,
            checkIns,
            archives,
        )
        let latestNicknames = Dictionary(
            grouping: resolvedMetadata.filter { $0.field == .nickname },
            by: \.deviceID,
        )
        .compactMapValues { $0.max(by: RecordingDeviceMetadataChange.isOrderedBefore) }
        let checkInsByDevice = Dictionary(uniqueKeysWithValues: resolvedCheckIns.map {
            ($0.deviceID, $0)
        })
        let archivesByDevice = Dictionary(grouping: resolvedArchives, by: \.deviceID)
            .compactMapValues { $0.min(by: { $0.archivedAt < $1.archivedAt }) }
        return resolvedProfiles
            .map {
                RecordingDevice(
                    profile: $0,
                    nicknameChange: latestNicknames[$0.id],
                    checkIn: checkInsByDevice[$0.id],
                    archive: archivesByDevice[$0.id],
                )
            }
            .sorted {
                if $0.lastSeenAt != $1.lastSeenAt { return $0.lastSeenAt > $1.lastSeenAt }
                return $0.id.storeURL.absoluteString < $1.id.storeURL.absoluteString
            }
    }

    public func recordingDeviceProfiles() async throws -> [RecordingDeviceProfile] {
        let context = readContext()
        var descriptor = FetchDescriptor<SDRecordingDeviceProfile>(
            sortBy: [SortDescriptor(\.registeredAt)],
        )
        descriptor.includePendingChanges = true
        let values: [RecordingDeviceProfile] = try context.fetch(descriptor).compactMap { record in
            let value = record.toValue()
            if value == nil { Self.logFault(forCorrupt: record) }
            return value
        }
        // CloudKit cannot enforce uniqueness. Profiles are immutable, so identical retries
        // converge naturally; a conflicting duplicate resolves deterministically to the
        // earliest registration and is prevented on every local write path below.
        return Dictionary(grouping: values, by: \.id)
            .compactMap { id, duplicates in
                if Set(duplicates).count > 1 {
                    Self.logImmutableConflict(
                        type: String(describing: RecordingDeviceProfile.self),
                        id: id.storeURL.absoluteString,
                        count: duplicates.count,
                    )
                }
                return duplicates.min {
                    if $0.registeredAt != $1.registeredAt {
                        return $0.registeredAt < $1.registeredAt
                    }
                    if $0.systemName != $1.systemName { return $0.systemName < $1.systemName }
                    if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
                    return $0.registrationEpochID.rawValue.uuidString
                        < $1.registrationEpochID.rawValue.uuidString
                }
            }
            .sorted { $0.id.storeURL.absoluteString < $1.id.storeURL.absoluteString }
    }

    public func addRecordingDeviceProfile(_ profile: RecordingDeviceProfile) async throws {
        let context = mutationContext()
        let id = profile.id.rawValue
        let existing = try context.fetch(
            FetchDescriptor<SDRecordingDeviceProfile>(predicate: #Predicate { $0.id == id }),
        )
        guard !existing.isEmpty else {
            context.insert(SDRecordingDeviceProfile(value: profile))
            return
        }
        guard existing.allSatisfy({ $0.toValue() == profile }) else {
            throw RecordingPersistenceError.conflictingImmutableRecord(id: id)
        }
        for duplicate in existing.dropFirst() {
            context.delete(duplicate)
        }
    }

    public func recordingDeviceMetadataChanges() async throws -> [RecordingDeviceMetadataChange] {
        let context = readContext()
        let epochID = try readEpochID(in: context)
        var descriptor = FetchDescriptor<SDRecordingDeviceMetadataChange>(
            sortBy: [SortDescriptor(\.revision), SortDescriptor(\.id)],
        )
        descriptor.includePendingChanges = true
        let values: [RecordingDeviceMetadataChange] = try context.fetch(descriptor)
            .compactMap { record in
                guard Self.belongs(record.epochID, to: epochID) else { return nil }
                let value = record.toValue()
                if value == nil { Self.logFault(forCorrupt: record) }
                return value
            }
        return Dictionary(grouping: values, by: \.id)
            .compactMap { id, duplicates in
                if Set(duplicates).count > 1 {
                    Self.logImmutableConflict(
                        type: String(describing: RecordingDeviceMetadataChange.self),
                        id: id.uuidString,
                        count: duplicates.count,
                    )
                }
                return duplicates.min(by: RecordingDeviceMetadataChange.isCanonicalBefore)
            }
            .sorted(by: RecordingDeviceMetadataChange.isOrderedBefore)
    }

    public func addRecordingDeviceMetadataChange(
        _ change: RecordingDeviceMetadataChange,
    ) async throws {
        let context = mutationContext()
        let epochID = mutationEpochID()
        let id = change.id
        let existing = try context.fetch(
            FetchDescriptor<SDRecordingDeviceMetadataChange>(predicate: #Predicate { $0.id == id }),
        )
        let active = existing.filter { Self.belongs($0.epochID, to: epochID) }
        guard !active.isEmpty else {
            context.insert(SDRecordingDeviceMetadataChange(value: change, epochID: epochID))
            return
        }
        guard active.allSatisfy({ $0.toValue() == change }) else {
            throw RecordingPersistenceError.conflictingImmutableRecord(id: id)
        }
        for duplicate in active.dropFirst() {
            context.delete(duplicate)
        }
    }

    public func recordingDeviceCheckIns() async throws -> [RecordingDeviceCheckIn] {
        let context = readContext()
        let epochID = try readEpochID(in: context)
        var descriptor = FetchDescriptor<SDRecordingDeviceCheckIn>(
            sortBy: [SortDescriptor(\.lastSeenAt, order: .reverse)],
        )
        descriptor.includePendingChanges = true
        let values: [RecordingDeviceCheckIn] = try context.fetch(descriptor).compactMap { record in
            guard Self.belongs(record.epochID, to: epochID) else { return nil }
            let value = record.toValue()
            if value == nil { Self.logFault(forCorrupt: record) }
            return value
        }
        return Dictionary(grouping: values, by: \.deviceID)
            .compactMap { _, duplicates in
                duplicates.max { RecordingDeviceCheckIn.isOlder($0, than: $1) }
            }
            .sorted { $0.deviceID.storeURL.absoluteString < $1.deviceID.storeURL.absoluteString }
    }

    public func setRecordingDeviceCheckIn(_ checkIn: RecordingDeviceCheckIn) async throws {
        let context = mutationContext()
        let epochID = mutationEpochID()
        let deviceID = checkIn.deviceID.rawValue
        let allExisting = try context.fetch(
            FetchDescriptor<SDRecordingDeviceCheckIn>(predicate: #Predicate {
                $0.deviceID == deviceID
            }),
        )
        let existing = allExisting.filter { Self.belongs($0.epochID, to: epochID) }
        guard let canonical = existing.first else {
            context.insert(SDRecordingDeviceCheckIn(value: checkIn, epochID: epochID))
            return
        }
        let current = existing.compactMap { $0.toValue() }
            .max { RecordingDeviceCheckIn.isOlder($0, than: $1) }
        let winner = if let current,
                        RecordingDeviceCheckIn.isOlder(checkIn, than: current)
        {
            current
        } else {
            checkIn
        }
        // Always copy the selected winner into the row we retain. `existing.first` is not
        // guaranteed to be the row `max` selected; retaining it unchanged could delete the
        // winner while collapsing CloudKit duplicates.
        canonical.update(from: winner, epochID: epochID)
        for duplicate in existing.dropFirst() {
            context.delete(duplicate)
        }
    }

    public func recordingAssignmentChanges() async throws -> [RecordingAssignmentChange] {
        let context = readContext()
        let epochID = try readEpochID(in: context)
        var descriptor = FetchDescriptor<SDRecordingAssignmentChange>(
            sortBy: [SortDescriptor(\.revision), SortDescriptor(\.id)],
        )
        descriptor.includePendingChanges = true
        let values = try context.fetch(descriptor)
            .filter { Self.belongs($0.epochID, to: epochID) }
            .compactMap { record -> RecordingAssignmentChange? in
                guard let value = record.toValue() else {
                    Self.logFault(forCorrupt: record)
                    return nil
                }
                return value
            }
        guard RecordingAssignmentChange.formValidPersistedTimeline(values) else {
            throw RecordingPersistenceError.incompleteAssignmentHistory
        }
        return Dictionary(grouping: values, by: \.id)
            .compactMap { _, duplicates in
                duplicates.min(by: RecordingAssignmentChange.isCanonicalBefore)
            }
            .sorted {
                $0.revision == $1.revision
                    ? $0.id.uuidString < $1.id.uuidString
                    : $0.revision < $1.revision
            }
    }

    public func addRecordingAssignmentChange(_ change: RecordingAssignmentChange) async throws {
        let context = mutationContext()
        let epochID = mutationEpochID()
        let id = change.id
        let existing = try context.fetch(
            FetchDescriptor<SDRecordingAssignmentChange>(predicate: #Predicate { $0.id == id }),
        ).filter { Self.belongs($0.epochID, to: epochID) }
        guard existing.isEmpty == false else {
            context.insert(SDRecordingAssignmentChange(value: change, epochID: epochID))
            return
        }
        guard existing.allSatisfy({ $0.toValue() == change }) else {
            throw RecordingPersistenceError.conflictingImmutableRecord(id: id)
        }
        for duplicate in existing.dropFirst() {
            context.delete(duplicate)
        }
    }

    public func recordingDeviceArchives() async throws -> [RecordingDeviceArchive] {
        let context = readContext()
        let epochID = try readEpochID(in: context)
        var descriptor = FetchDescriptor<SDRecordingDeviceArchive>(
            sortBy: [SortDescriptor(\.archivedAt), SortDescriptor(\.id)],
        )
        descriptor.includePendingChanges = true
        let records: [SDRecordingDeviceArchive] = try context.fetch(descriptor)
        return records
            .filter { Self.belongs($0.epochID, to: epochID) }
            .compactMap { $0.toValue() }
    }

    public func addRecordingDeviceArchive(_ archive: RecordingDeviceArchive) async throws {
        let context = mutationContext()
        let epochID = mutationEpochID()
        let id = archive.id
        let existing = try context.fetch(
            FetchDescriptor<SDRecordingDeviceArchive>(predicate: #Predicate { $0.id == id }),
        ).filter { Self.belongs($0.epochID, to: epochID) }
        guard existing.isEmpty == false else {
            context.insert(SDRecordingDeviceArchive(value: archive, epochID: epochID))
            return
        }
        guard existing.allSatisfy({ $0.toValue() == archive }) else {
            throw RecordingPersistenceError.conflictingImmutableRecord(id: id)
        }
        for duplicate in existing.dropFirst() {
            context.delete(duplicate)
        }
    }

    public func write(evidence: Evidence, blob: Data?) async throws {
        let context = mutationContext()
        let epochID = mutationEpochID()
        let id = evidence.id
        let allExisting = try context.fetch(
            FetchDescriptor<SDEvidence>(predicate: #Predicate { $0.id == id }),
        )
        let active = allExisting.filter { Self.belongs($0.epochID, to: epochID) }
        if let existing = active.first {
            // Treat `blob == nil` as "no change" so a metadata-only edit
            // (note, kind, region) does not wipe a previously stored
            // attachment. Callers that need to remove the blob explicitly
            // use `delete(for:)` from the `EvidenceBlobStore` API.
            existing.update(from: evidence, blob: blob ?? existing.blob, epochID: epochID)
            for duplicate in active.dropFirst() {
                context.delete(duplicate)
            }
        } else {
            // An inactive same-id row is retained only as superseded sync history. Never carry
            // its attachment bytes into the current epoch when a backup intentionally restores
            // metadata without a declared asset.
            context.insert(SDEvidence(value: evidence, blob: blob, epochID: epochID))
        }
    }

    public func evidence(in interval: DateInterval) async throws -> [Evidence] {
        let context = readContext()
        let epochID = try readEpochID(in: context)
        let start = interval.start
        let end = interval.end
        var descriptor = FetchDescriptor<SDEvidence>(
            predicate: #Predicate {
                if let capturedAt = $0.capturedAt {
                    capturedAt >= start && capturedAt < end
                } else {
                    false
                }
            },
            sortBy: [SortDescriptor(\.capturedAt)],
        )
        descriptor.includePendingChanges = true
        return try Self.logger.measure(.fetchEvidence) {
            try context.fetch(descriptor).compactMap { record in
                guard Self.belongs(record.epochID, to: epochID) else { return nil }
                let value = record.toValue()
                if value == nil { Self.logFault(forCorrupt: record) }
                return value
            }
        }
    }

    public func allEvidence() async throws -> [Evidence] {
        let context = readContext()
        let epochID = try readEpochID(in: context)
        var descriptor = FetchDescriptor<SDEvidence>(sortBy: [SortDescriptor(\.capturedAt)])
        descriptor.includePendingChanges = true
        return try context.fetch(descriptor).compactMap { record in
            guard Self.belongs(record.epochID, to: epochID) else { return nil }
            let value = record.toValue()
            if value == nil { Self.logFault(forCorrupt: record) }
            return value
        }
    }

    public func evidenceBlob(for id: UUID) async throws -> Data? {
        let context = readContext()
        let epochID = try readEpochID(in: context)
        let descriptor = FetchDescriptor<SDEvidence>(predicate: #Predicate { $0.id == id })
        // Blobs live in external storage, so this is a file read behind a fetch
        // — the one evidence read whose cost scales with the attachment.
        return try Self.logger.measure(.fetchEvidenceBlob) {
            try context.fetch(descriptor).first(where: {
                Self.belongs($0.epochID, to: epochID)
            })?.blob
        }
    }

    public func write(blob: Data, for id: UUID) async throws {
        let context = mutationContext()
        let epochID = mutationEpochID()
        let descriptor = FetchDescriptor<SDEvidence>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(descriptor).first(where: {
            Self.belongs($0.epochID, to: epochID)
        }) else { return }
        record.blob = blob
    }

    public func read(for id: UUID) async throws -> Data? {
        try await evidenceBlob(for: id)
    }

    public func delete(for id: UUID) async throws {
        let context = mutationContext()
        let epochID = mutationEpochID()
        let descriptor = FetchDescriptor<SDEvidence>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(descriptor).first(where: {
            Self.belongs($0.epochID, to: epochID)
        }) else { return }
        record.blob = nil
    }

    public func setManualDay(_ day: DayPresence) async throws {
        let context = mutationContext()
        let epochID = mutationEpochID()
        let key = day.day.description
        let existing = try context.fetch(
            FetchDescriptor<SDManualDay>(predicate: #Predicate { $0.dayKey == key }),
        ).filter { Self.belongs($0.epochID, to: epochID) }
        if let canonical = existing.first {
            canonical.update(
                from: Self.resolved(incoming: day, existing: canonical),
                epochID: epochID,
            )
            for duplicate in existing.dropFirst() {
                context.delete(duplicate)
            }
        } else {
            context.insert(SDManualDay(value: day, epochID: epochID))
        }
    }

    /// Decide how an incoming manual write combines with the row already on
    /// disk for that day. An additive (non-authoritative) write — e.g. a
    /// Settings/range backfill — must not silently downgrade a user's
    /// authoritative relabel: the row stays authoritative and the backfilled
    /// regions union in. Every other case replaces wholesale (authoritative
    /// overrides and additive-over-additive alike), preserving prior behavior.
    ///
    /// The incoming write's `audit` always wins: it reflects the most recent
    /// manual action (its note, its capture-time GPS), so even when regions
    /// can't be downgraded the audit trail tracks the latest edit.
    private static func resolved(incoming day: DayPresence, existing: SDManualDay) -> DayPresence {
        guard existing.isAuthoritative, !day.isAuthoritative else { return day }
        let existingRegions = Set(existing.regionRaws.compactMap { Region(rawValue: $0) })
        return DayPresence(
            day: day.day,
            regions: existingRegions.union(day.regions),
            isAuthoritative: true,
            audit: day.audit,
        )
    }

    public func clearManualDay(_ day: CalendarDay) async throws {
        let context = mutationContext()
        let epochID = mutationEpochID()
        let key = day.description
        let descriptor = FetchDescriptor<SDManualDay>(predicate: #Predicate { $0.dayKey == key })
        for record in try context.fetch(descriptor)
            where Self.belongs(record.epochID, to: epochID)
        {
            context.delete(record)
        }
    }

    public func manualDays(in dayRange: ClosedRange<CalendarDay>) async throws -> [DayPresence] {
        let context = readContext()
        let epochID = try readEpochID(in: context)
        // ISO `YYYY-MM-DD` sorts lexicographically, so a string range is a
        // correct inclusive day range.
        let low = dayRange.lowerBound.description
        let high = dayRange.upperBound.description
        var descriptor = FetchDescriptor<SDManualDay>(
            predicate: #Predicate {
                if let dayKey = $0.dayKey {
                    dayKey >= low && dayKey <= high
                } else {
                    false
                }
            },
            sortBy: [SortDescriptor(\.dayKey)],
        )
        descriptor.includePendingChanges = true
        return try Self.logger.measure(.fetchManualDays) {
            try context.fetch(descriptor).compactMap { record in
                guard Self.belongs(record.epochID, to: epochID) else { return nil }
                let value = record.toValue()
                if value == nil { Self.logFault(forCorrupt: record) }
                return value
            }
        }
    }

    public func allManualDays() async throws -> [DayPresence] {
        let context = readContext()
        let epochID = try readEpochID(in: context)
        var descriptor = FetchDescriptor<SDManualDay>(sortBy: [SortDescriptor(\.dayKey)])
        descriptor.includePendingChanges = true
        return try context.fetch(descriptor).compactMap { record in
            guard Self.belongs(record.epochID, to: epochID) else { return nil }
            let value = record.toValue()
            if value == nil { Self.logFault(forCorrupt: record) }
            return value
        }
    }

    public func clear(
        in interval: DateInterval,
        manualDays dayRange: ClosedRange<CalendarDay>,
    ) async throws {
        let context = mutationContext()
        let epochID = mutationEpochID()
        let start = interval.start
        let end = interval.end
        let samples = try context.fetch(
            FetchDescriptor<SDLocationSample>(predicate: #Predicate {
                if let timestamp = $0.timestamp {
                    timestamp >= start && timestamp < end
                } else {
                    false
                }
            }),
        )
        for record in samples where Self.belongs(record.epochID, to: epochID) {
            context.delete(record)
        }
        let evidences = try context.fetch(
            FetchDescriptor<SDEvidence>(predicate: #Predicate {
                if let capturedAt = $0.capturedAt {
                    capturedAt >= start && capturedAt < end
                } else {
                    false
                }
            }),
        )
        for record in evidences where Self.belongs(record.epochID, to: epochID) {
            context.delete(record)
        }
        let low = dayRange.lowerBound.description
        let high = dayRange.upperBound.description
        let manuals = try context.fetch(
            FetchDescriptor<SDManualDay>(predicate: #Predicate {
                if let dayKey = $0.dayKey {
                    dayKey >= low && dayKey <= high
                } else {
                    false
                }
            }),
        )
        for record in manuals where Self.belongs(record.epochID, to: epochID) {
            context.delete(record)
        }
    }

    public func dismissedIssueIDs() async throws -> Set<DataIssueID> {
        let context = readContext()
        let epochID = try readEpochID(in: context)
        var descriptor = FetchDescriptor<SDDismissedIssue>()
        descriptor.includePendingChanges = true
        let ids = try context.fetch(descriptor).compactMap { record -> DataIssueID? in
            guard Self.belongs(record.epochID, to: epochID) else { return nil }
            let value = record.toValue()
            if value == nil { Self.logFault(forCorrupt: record) }
            return value?.id
        }
        return Set(ids)
    }

    public func allDismissedIssues() async throws -> [DismissedIssue] {
        let context = readContext()
        let epochID = try readEpochID(in: context)
        var descriptor = FetchDescriptor<SDDismissedIssue>(sortBy: [SortDescriptor(\.key)])
        descriptor.includePendingChanges = true
        return try context.fetch(descriptor).compactMap { record in
            guard Self.belongs(record.epochID, to: epochID) else { return nil }
            let value = record.toValue()
            if value == nil { Self.logFault(forCorrupt: record) }
            return value
        }
    }

    public func setIssueDismissed(_ dismissed: Bool, id: DataIssueID) async throws {
        let context = mutationContext()
        let epochID = mutationEpochID()
        let key = id.storeURL.absoluteString
        let descriptor = FetchDescriptor<SDDismissedIssue>(predicate: #Predicate { $0.key == key })
        let existing = try context.fetch(descriptor)
            .filter { Self.belongs($0.epochID, to: epochID) }
        if dismissed {
            guard existing.isEmpty else { return }
            context.insert(SDDismissedIssue(key: key, dismissedAt: Date(), epochID: epochID))
        } else {
            for record in existing {
                context.delete(record)
            }
        }
    }

    public func restoreDismissedIssue(_ issue: DismissedIssue) async throws {
        let context = mutationContext()
        let epochID = mutationEpochID()
        let key = issue.id.storeURL.absoluteString
        let descriptor = FetchDescriptor<SDDismissedIssue>(predicate: #Predicate { $0.key == key })
        if let record = try context.fetch(descriptor).first(where: {
            Self.belongs($0.epochID, to: epochID)
        }) {
            record.dismissedAt = issue.dismissedAt
        } else {
            context.insert(SDDismissedIssue(
                key: key,
                dismissedAt: issue.dismissedAt,
                epochID: epochID,
            ))
        }
    }

    // MARK: - Tracked regions

    public func trackedRegions() async throws -> Set<Region> {
        let context = readContext()
        let epochID = try readEpochID(in: context)
        var descriptor = FetchDescriptor<SDTrackedRegion>()
        descriptor.includePendingChanges = true
        let ids: [String] = try context.fetch(descriptor).compactMap { record in
            guard Self.belongs(record.epochID, to: epochID) else { return nil }
            return record.regionID
        }
        // No rows means the user hasn't chosen yet — fall back to the default
        // set (applied identically in every process). Once any row exists, the
        // tracked set is exactly the persisted rows.
        guard !ids.isEmpty else { return Self.defaultTrackedRegions }
        // Unknown ids (e.g. a region dropped from the catalog) are filtered out
        // rather than crashing. Surface it: a stored id we can't resolve is a
        // degraded state — and if *every* id drops, the resulting empty set makes
        // everything attribute to `.other`, which must not be silent.
        var resolved: Set<Region> = []
        var unknown: [String] = []
        for id in ids {
            if let region = Region(rawValue: id) {
                resolved.insert(region)
            } else {
                unknown.append(id)
            }
        }
        if !unknown.isEmpty {
            Self.logger {
                .ignoredUnknownTrackedRegions(ids: unknown.sorted())
            }
        }
        return resolved
    }

    public func setTrackedRegion(_ tracked: Bool, id: String) async throws {
        let context = mutationContext()
        let epochID = mutationEpochID()
        let descriptor = FetchDescriptor<SDTrackedRegion>(
            predicate: #Predicate { $0.regionID == id },
        )
        let existing = try context.fetch(descriptor)
            .filter { Self.belongs($0.epochID, to: epochID) }
        if tracked {
            // Dedupe defensively: CloudKit can't enforce uniqueness, so collapse
            // any accidental duplicate rows to one on write.
            guard existing.isEmpty else {
                for extra in existing.dropFirst() {
                    context.delete(extra)
                }
                return
            }
            context.insert(SDTrackedRegion(regionID: id, epochID: epochID))
        } else {
            // TODO: Untracking deletes the row, which drops the region from the
            // attributor's load set — so re-aggregating a past year would
            // re-attribute that region's GPS days to `.other` (manual days,
            // stored as region sets, are unaffected). Now user-reachable (the
            // onboarding picker and the Settings region editor remove picks via
            // `removePrimaryRegion` → here), so switching to a soft-delete (mark
            // the row inactive, never delete) and having the attributor load
            // every ever-tracked region — so past reports stay stable while
            // "active" drives the UI/primary set — is worth doing.
            for record in existing {
                context.delete(record)
            }
        }
    }

    public func primaryRegions() async throws -> [PrimaryRegion] {
        let context = readContext()
        let epochID = try readEpochID(in: context)
        var descriptor = FetchDescriptor<SDTrackedRegion>()
        descriptor.includePendingChanges = true
        let rows = try context.fetch(descriptor)
            .filter { Self.belongs($0.epochID, to: epochID) }
        // No rows means the user hasn't chosen yet — mirror `trackedRegions()`'s
        // default fallback so the picker/customization UI opens on the
        // out-of-the-box set rather than empty.
        guard !rows.isEmpty else {
            return Region.inCanonicalOrder(Self.defaultTrackedRegions)
                .enumerated()
                .map { PrimaryRegion(region: $1, appearance: nil, order: $0) }
        }
        var resolved: [PrimaryRegion] = []
        var unknown: [String] = []
        // De-dupe by id (CloudKit can't enforce uniqueness): first row per id
        // wins, preferring one that carries an appearance/order.
        var seen: Set<String> = []
        let sorted = rows.sorted { lhs, rhs in
            let l = lhs.orderIndex ?? Int.max
            let r = rhs.orderIndex ?? Int.max
            if l != r { return l < r }
            return (lhs.regionID ?? "") < (rhs.regionID ?? "")
        }
        for row in sorted {
            guard let id = row.regionID else { continue }
            guard let region = Region(rawValue: id) else {
                unknown.append(id)
                continue
            }
            guard seen.insert(id).inserted else { continue }
            resolved.append(PrimaryRegion(
                region: region,
                appearance: row.appearanceValue,
                order: row.orderIndex ?? resolved.count,
            ))
        }
        if !unknown.isEmpty {
            Self.logger {
                .ignoredUnknownPrimaryRegions(ids: unknown.sorted())
            }
        }
        return resolved
    }

    public func setPrimaryRegions(_ regions: [PrimaryRegion]) async throws {
        let context = mutationContext()
        let epochID = mutationEpochID()
        let desiredIDs = Set(regions.map(\.region.rawValue))
        // Delete every tracked row not in the desired set (and any row with a
        // nil id, which we can't resolve) — removals happen by omission.
        for row in try context.fetch(FetchDescriptor<SDTrackedRegion>())
            where Self.belongs(row.epochID, to: epochID)
        {
            if let id = row.regionID, desiredIDs.contains(id) { continue }
            context.delete(row)
        }
        // Upsert each desired region's row (membership + appearance + order),
        // collapsing any accidental duplicate rows to one (CloudKit can't
        // enforce uniqueness).
        for entry in regions {
            let id = entry.region.rawValue
            let existing = try context.fetch(FetchDescriptor<SDTrackedRegion>(
                predicate: #Predicate { $0.regionID == id },
            )).filter { Self.belongs($0.epochID, to: epochID) }
            let row: SDTrackedRegion
            if let first = existing.first {
                for extra in existing.dropFirst() {
                    context.delete(extra)
                }
                row = first
            } else {
                row = SDTrackedRegion(regionID: id, epochID: epochID)
                context.insert(row)
            }
            row.apply(appearance: entry.appearance, order: entry.order)
        }
    }

    private static func logFault<Record>(forCorrupt _: Record) {
        logger { .droppedCorruptRecord(type: String(describing: Record.self)) }
    }

    private static func logImmutableConflict(type: String, id: String, count: Int) {
        logger { .resolvedConflictingImmutableRecords(type: type, id: id, count: count) }
    }
}

/// Installation-scoped commit proof for the backup import two-phase protocol.
@Model
final class SDBackupImportReceipt {
    var id: UUID?
    var installationID: UUID?
    var epochID: UUID?

    init() {}

    convenience init(value: BackupImportReceipt) {
        self.init()
        id = value.id
        installationID = value.installationID.rawValue
        epochID = value.dataEpochID.rawValue
    }

    func toValue() -> BackupImportReceipt? {
        guard let id, let installationID, let epochID else { return nil }
        return BackupImportReceipt(
            id: id,
            installationID: RecordingDeviceID(rawValue: installationID),
            dataEpochID: WhereDataEpochID(rawValue: epochID),
        )
    }
}

// MARK: - SwiftData models (internal)

/// Append-only account-wide logical-generation change. Revision zero is synthesized in Core;
/// only destructive rotations are persisted here.
@Model
final class SDWhereDataEpoch {
    var id: UUID?
    /// Legacy scalar parent. New multi-parent rows leave this nil so delivery of the new array
    /// cannot be mistaken for a complete one-parent command before all CloudKit fields arrive.
    var parentID: UUID?
    var parentIDs: [UUID]?
    var revision: Int64?
    var changedAt: Date?
    var changedByDeviceID: UUID?
    var reasonRaw: String?

    init() {}

    convenience init(value: WhereDataEpoch) {
        self.init()
        id = value.id.rawValue
        parentID = nil
        parentIDs = value.parentIDs.map(\.rawValue)
        revision = value.revision
        changedAt = value.changedAt
        changedByDeviceID = value.changedByDeviceID?.rawValue
        reasonRaw = value.reason.rawValue
    }

    func toValue() -> WhereDataEpoch? {
        guard let id,
              let revision,
              revision > 0,
              let changedAt,
              let changedByDeviceID,
              let reasonRaw,
              let reason = WhereDataEpochReason(rawValue: reasonRaw),
              reason.isDestructive
        else { return nil }
        let resolvedParentIDs: [UUID]
        if let parentIDs {
            resolvedParentIDs = parentIDs
        } else if let parentID {
            resolvedParentIDs = [parentID]
        } else {
            return nil
        }
        guard resolvedParentIDs.isEmpty == false,
              Set(resolvedParentIDs).count == resolvedParentIDs.count,
              resolvedParentIDs.contains(id) == false
        else { return nil }
        return WhereDataEpoch(
            id: WhereDataEpochID(rawValue: id),
            parentIDs: resolvedParentIDs.map(WhereDataEpochID.init(rawValue:)),
            revision: revision,
            changedAt: changedAt,
            changedByDeviceID: RecordingDeviceID(rawValue: changedByDeviceID),
            reason: reason,
        )
    }
}

@Model
final class SDLocationSample {
    /// Nil belongs to the implicit initial epoch, preserving rows from builds before epochs.
    var epochID: UUID?
    var id: UUID?
    var timestamp: Date?
    var latitude: Double?
    var longitude: Double?
    var horizontalAccuracy: Double?
    /// Discriminator string from `SampleSource.discriminator`.
    var sourceRaw: String?
    /// Populated only when `sourceRaw == "evidenceImplied"`.
    var evidenceId: UUID?
    /// Populated only when `sourceRaw == "evidenceImplied"`. Stores the
    /// `EvidenceKind.discriminator` of the originating evidence; the
    /// `.other` label is not preserved here (fetch the `Evidence` row
    /// for that).
    var evidenceKindRaw: String?
    /// Installation that produced an automatic sample. Nil on legacy rows and
    /// manual/evidence-implied samples.
    var recordingDeviceID: UUID?

    init() {}

    convenience init(value: LocationSample, epochID: WhereDataEpochID) {
        self.init()
        update(from: value, epochID: epochID)
    }

    func update(from value: LocationSample, epochID: WhereDataEpochID) {
        self.epochID = epochID.rawValue
        id = value.id
        timestamp = value.timestamp
        latitude = value.coordinate.latitude
        longitude = value.coordinate.longitude
        horizontalAccuracy = value.horizontalAccuracy
        sourceRaw = value.source.discriminator
        evidenceId = value.source.evidenceId
        evidenceKindRaw = value.source.evidenceKind?.discriminator
        recordingDeviceID = value.recordingDeviceID?.rawValue
    }

    func toValue() -> LocationSample? {
        guard let id, let timestamp, let latitude, let longitude, let horizontalAccuracy,
              let sourceRaw
        else { return nil }
        guard let source = SampleSource.fromDiscriminator(
            sourceRaw,
            evidenceId: evidenceId,
            evidenceKindRaw: evidenceKindRaw,
        ) else { return nil }
        return LocationSample(
            id: id,
            timestamp: timestamp,
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            horizontalAccuracy: horizontalAccuracy,
            source: source,
            recordingDeviceID: recordingDeviceID.map(RecordingDeviceID.init(rawValue:)),
        )
    }
}

@Model
final class SDEvidence {
    var epochID: UUID?
    var id: UUID?
    /// `EvidenceKind.discriminator` ("planeTicket", "other", etc.).
    var kindRaw: String?
    /// User-supplied label for the `.other` catch-all. Nil for every
    /// other kind.
    var otherLabel: String?
    var capturedAt: Date?
    var note: String?
    var regionRaw: String?
    /// `EvidenceContentType.discriminator` ("pdf", "image", "other", ...).
    /// Optional only because all SwiftData fields must be optional
    /// for CloudKit; the value-level `Evidence.contentType` is
    /// required, and `toValue()` falls back to `.other(nil)` for
    /// missing/unknown discriminators so legacy rows stay readable.
    var contentTypeDiscriminator: String?
    /// User-supplied label for `EvidenceContentType.other`. Nil for
    /// every other content type.
    var contentTypeOtherLabel: String?
    @Attribute(.externalStorage) var blob: Data?

    init() {}

    convenience init(value: Evidence, blob: Data?, epochID: WhereDataEpochID) {
        self.init()
        update(from: value, blob: blob, epochID: epochID)
    }

    func update(from value: Evidence, blob: Data?, epochID: WhereDataEpochID) {
        self.epochID = epochID.rawValue
        id = value.id
        kindRaw = value.kind.discriminator
        otherLabel = if case let .other(label) = value.kind { label } else { nil }
        capturedAt = value.capturedAt
        note = value.note
        regionRaw = value.region?.rawValue
        contentTypeDiscriminator = value.contentType.discriminator
        contentTypeOtherLabel = if case let .other(label) = value.contentType { label } else { nil }
        self.blob = blob
    }

    func toValue() -> Evidence? {
        guard let id, let kindRaw, let capturedAt else { return nil }
        let kind = EvidenceKind.fromDiscriminator(kindRaw, otherLabel: otherLabel) ?? .other(nil)
        let contentType = contentTypeDiscriminator
            .flatMap { EvidenceContentType.fromDiscriminator($0, otherLabel: contentTypeOtherLabel)
            }
            ?? .other(nil)
        return Evidence(
            id: id,
            kind: kind,
            capturedAt: capturedAt,
            region: regionRaw.flatMap { Region(rawValue: $0) },
            note: note,
            contentType: contentType,
        )
    }
}

@Model
final class SDManualDay {
    var epochID: UUID?
    /// Canonical, timezone-independent identity: the day's `CalendarDay` ISO
    /// string (`YYYY-MM-DD`). Optional only because the CloudKit mirror requires
    /// it; a row that somehow has no `dayKey` can't be placed on a day and is
    /// dropped (fault-logged) by `toValue()`.
    var dayKey: String?
    /// Whether this manual day replaces (rather than unions with) GPS for its
    /// date. Defaults to `false` (additive) — a CloudKit-safe default that keeps
    /// the column non-optional.
    var isAuthoritative: Bool = false
    var regionRaws: [String] = []

    // Audit metadata for a user-made entry (`ManualEntryAudit`). All optional so
    // the CloudKit mirror stays lightweight-migration-safe; rows written before
    // audit existed (and GPS-derived days) decode with no audit. `auditRecordedAt`
    // is the presence-of-audit discriminator — the location fields are populated
    // together only when a fix was captured.
    var note: String?
    var auditRecordedAt: Date?
    var auditLatitude: Double?
    var auditLongitude: Double?
    var auditAccuracy: Double?
    var auditLocationTimestamp: Date?

    init() {}

    convenience init(value: DayPresence, epochID: WhereDataEpochID) {
        self.init()
        update(from: value, epochID: epochID)
    }

    func update(from value: DayPresence, epochID: WhereDataEpochID) {
        self.epochID = epochID.rawValue
        dayKey = value.day.description
        regionRaws = value.regions.map(\.rawValue).sorted()
        isAuthoritative = value.isAuthoritative
        applyAudit(value.audit)
    }

    private func applyAudit(_ audit: ManualEntryAudit?) {
        note = audit?.note
        auditRecordedAt = audit?.recordedAt
        auditLatitude = audit?.location?.coordinate.latitude
        auditLongitude = audit?.location?.coordinate.longitude
        auditAccuracy = audit?.location?.horizontalAccuracy
        auditLocationTimestamp = audit?.location?.timestamp
    }

    func toValue() -> DayPresence? {
        guard let day = resolvedDay() else { return nil }
        return DayPresence(
            day: day,
            regions: Set(regionRaws.compactMap { Region(rawValue: $0) }),
            isAuthoritative: isAuthoritative,
            audit: auditValue(),
        )
    }

    /// The record's `CalendarDay`, parsed from the persisted `dayKey`. Returns
    /// `nil` for a row with no (or an unparseable) `dayKey` — an impossible
    /// state for a row this build wrote, so the caller drops it.
    private func resolvedDay() -> CalendarDay? {
        dayKey.flatMap(CalendarDay.init(iso:))
    }

    private func auditValue() -> ManualEntryAudit? {
        guard let auditRecordedAt else { return nil }
        return ManualEntryAudit(
            recordedAt: auditRecordedAt,
            note: note,
            location: capturedLocation(),
        )
    }

    private func capturedLocation() -> CapturedLocation? {
        guard let auditLatitude,
              let auditLongitude,
              let auditAccuracy,
              let auditLocationTimestamp
        else { return nil }
        return CapturedLocation(
            coordinate: Coordinate(latitude: auditLatitude, longitude: auditLongitude),
            horizontalAccuracy: auditAccuracy,
            timestamp: auditLocationTimestamp,
        )
    }
}

@Model
final class SDDismissedIssue {
    var epochID: UUID?
    /// The dismissed issue's identity, stored as its `DataIssueID` `store://`
    /// URL string (`id.storeURL.absoluteString`). A plain string column so
    /// `#Predicate` dedup/upsert stays a real query.
    var key: String?
    var dismissedAt: Date?

    init() {}

    init(key: String, dismissedAt: Date, epochID: WhereDataEpochID) {
        self.epochID = epochID.rawValue
        self.key = key
        self.dismissedAt = dismissedAt
    }

    func toValue() -> DismissedIssue? {
        guard let key, let dismissedAt,
              let url = URL(string: key),
              let id = DataIssueID(storeURL: url)
        else { return nil }
        return DismissedIssue(id: id, dismissedAt: dismissedAt)
    }
}

/// One tracked region, stored as a row (not a single blob of ids) so concurrent
/// cross-device edits merge: adding different regions on two devices keeps both,
/// and add/add of the same region collapses to one on read (`trackedRegions()`
/// returns a `Set`). `regionID` is `Region.rawValue`; optional per the CloudKit
/// mirror's requirement.
///
/// The `colorRaw` / `emoji` / `symbolName` / `orderIndex` fields carry the
/// region's user-picked ``RegionAppearance`` and pick order. All optional —
/// both because CloudKit requires it and because a row can be tracked without a
/// chosen look yet (the default set, or a legacy row); a resolved appearance
/// needs all three style fields present.
@Model
final class SDTrackedRegion {
    var epochID: UUID?
    var regionID: String?
    var colorRaw: String?
    var emoji: String?
    var symbolName: String?
    var orderIndex: Int?

    init() {}

    init(regionID: String, epochID: WhereDataEpochID) {
        self.epochID = epochID.rawValue
        self.regionID = regionID
    }

    /// The stored appearance, or `nil` when the row has no complete look yet.
    var appearanceValue: RegionAppearance? {
        guard let colorRaw, let color = RegionColorToken(rawValue: colorRaw),
              let emoji, let symbolName
        else { return nil }
        return RegionAppearance(color: color, emoji: emoji, symbolName: symbolName)
    }

    /// Overwrite the stored appearance (clearing the style fields when `nil`)
    /// and pick order.
    func apply(appearance: RegionAppearance?, order: Int?) {
        colorRaw = appearance?.color.rawValue
        emoji = appearance?.emoji
        symbolName = appearance?.symbolName
        orderIndex = order
    }
}

/// Immutable identity row written once by its installation. Every field is optional because
/// CloudKit may materialize a partial record before all fields arrive.
@Model
final class SDRecordingDeviceProfile {
    var id: UUID?
    var systemName: String?
    var kindRaw: String?
    var registeredAt: Date?
    var registrationEpochID: UUID?

    init() {}

    convenience init(value: RecordingDeviceProfile) {
        self.init()
        id = value.id.rawValue
        systemName = value.systemName
        kindRaw = value.kind.rawValue
        registeredAt = value.registeredAt
        registrationEpochID = value.registrationEpochID.rawValue
    }

    func toValue() -> RecordingDeviceProfile? {
        guard let id,
              let systemName,
              let kindRaw,
              let kind = RecordingDeviceKind(rawValue: kindRaw),
              let registeredAt,
              let registrationEpochID
        else { return nil }
        return RecordingDeviceProfile(
            id: RecordingDeviceID(rawValue: id),
            systemName: systemName,
            kind: kind,
            registeredAt: registeredAt,
            registrationEpochID: WhereDataEpochID(rawValue: registrationEpochID),
        )
    }
}

/// Append-only nickname edit. Effective archive authority is a policy state.
@Model
final class SDRecordingDeviceMetadataChange {
    var epochID: UUID?
    var id: UUID?
    var deviceID: UUID?
    var fieldRaw: String?
    var revision: Int64?
    var changedAt: Date?
    var changedByDeviceID: UUID?
    var nickname: String?

    init() {}

    convenience init(value: RecordingDeviceMetadataChange, epochID: WhereDataEpochID) {
        self.init()
        self.epochID = epochID.rawValue
        id = value.id
        deviceID = value.deviceID.rawValue
        fieldRaw = value.field.rawValue
        revision = value.revision
        changedAt = value.changedAt
        changedByDeviceID = value.changedByDeviceID.rawValue
        nickname = value.nickname
    }

    func toValue() -> RecordingDeviceMetadataChange? {
        guard let id,
              let deviceID,
              let fieldRaw,
              let field = RecordingDeviceMetadataField(rawValue: fieldRaw),
              let revision,
              revision >= 0,
              let changedAt,
              let changedByDeviceID
        else { return nil }
        guard field == .nickname else { return nil }
        return RecordingDeviceMetadataChange(
            id: id,
            deviceID: RecordingDeviceID(rawValue: deviceID),
            revision: revision,
            changedAt: changedAt,
            changedByDeviceID: RecordingDeviceID(rawValue: changedByDeviceID),
            nickname: nickname,
        )
    }
}

/// Target-owned acknowledgement/check-in row. No other installation writes this row during
/// normal operation, so a whole-value update cannot clobber user metadata.
@Model
final class SDRecordingDeviceCheckIn {
    var epochID: UUID?
    var deviceID: UUID?
    var revision: Int64?
    var lastSeenAt: Date?
    var appliedAt: Date?
    var lastAppliedAssignmentChangeID: UUID?
    /// Singleton destructive event id or deterministic multi-head frontier digest. The field name
    /// predates multi-parent policy and remains stable for CloudKit compatibility.
    var lastDiscardedAssignmentChangeID: UUID?
    var statusRaw: String?

    init() {}

    convenience init(value: RecordingDeviceCheckIn, epochID: WhereDataEpochID) {
        self.init()
        update(from: value, epochID: epochID)
    }

    func update(from value: RecordingDeviceCheckIn, epochID: WhereDataEpochID) {
        self.epochID = epochID.rawValue
        deviceID = value.deviceID.rawValue
        revision = value.revision
        lastSeenAt = value.lastSeenAt
        appliedAt = value.appliedAt
        lastAppliedAssignmentChangeID = value.lastAppliedAssignmentChangeID
        lastDiscardedAssignmentChangeID = value.lastDiscardedAssignmentChangeID
        statusRaw = value.status.rawValue
    }

    func toValue() -> RecordingDeviceCheckIn? {
        guard let deviceID,
              let revision,
              revision >= 0,
              let lastSeenAt,
              let appliedAt,
              let lastAppliedAssignmentChangeID,
              let statusRaw,
              let status = RecordingDeviceStatus(rawValue: statusRaw),
              status != .unknown
        else { return nil }
        return RecordingDeviceCheckIn(
            deviceID: RecordingDeviceID(rawValue: deviceID),
            revision: revision,
            lastSeenAt: lastSeenAt,
            appliedAt: appliedAt,
            lastAppliedAssignmentChangeID: lastAppliedAssignmentChangeID,
            lastDiscardedAssignmentFrontierToken: lastDiscardedAssignmentChangeID.map {
                RecordingAssignmentCleanupToken(rawValue: $0)
            },
            status: status,
        )
    }
}

/// Account-wide automatic-recording assignment command.
@Model
final class SDRecordingAssignmentChange {
    var epochID: UUID?
    var id: UUID?
    var parentIDs: [UUID]?
    var revision: Int64?
    var issuedAt: Date?
    var issuedByDeviceID: UUID?
    var effectiveAt: Date?
    var assignedDeviceID: UUID?
    var reasonRaw: String?

    init() {}

    convenience init(value: RecordingAssignmentChange, epochID: WhereDataEpochID) {
        self.init()
        self.epochID = epochID.rawValue
        id = value.id
        parentIDs = value.parentIDs
        revision = value.revision
        issuedAt = value.issuedAt
        issuedByDeviceID = value.issuedByDeviceID.rawValue
        effectiveAt = value.effectiveAt
        assignedDeviceID = value.assignedDeviceID?.rawValue
        reasonRaw = value.reason.rawValue
    }

    func toValue() -> RecordingAssignmentChange? {
        guard let id,
              let parentIDs,
              let revision,
              let issuedAt,
              let issuedByDeviceID,
              let effectiveAt,
              let reasonRaw,
              let reason = RecordingAssignmentReason(rawValue: reasonRaw),
              (revision == 0) == parentIDs.isEmpty
        else { return nil }
        return RecordingAssignmentChange(
            id: id,
            parentIDs: parentIDs,
            revision: revision,
            issuedAt: issuedAt,
            issuedByDeviceID: RecordingDeviceID(rawValue: issuedByDeviceID),
            effectiveAt: effectiveAt,
            assignedDeviceID: assignedDeviceID.map(RecordingDeviceID.init(rawValue:)),
            reason: reason,
        )
    }
}

/// Irreversible installation archive tombstone.
@Model
final class SDRecordingDeviceArchive {
    var epochID: UUID?
    var id: UUID?
    var deviceID: UUID?
    var archivedAt: Date?
    var archivedByDeviceID: UUID?

    init() {}

    convenience init(value: RecordingDeviceArchive, epochID: WhereDataEpochID) {
        self.init()
        self.epochID = epochID.rawValue
        id = value.id
        deviceID = value.deviceID.rawValue
        archivedAt = value.archivedAt
        archivedByDeviceID = value.archivedByDeviceID.rawValue
    }

    func toValue() -> RecordingDeviceArchive? {
        guard let id, let deviceID, let archivedAt, let archivedByDeviceID else { return nil }
        return RecordingDeviceArchive(
            id: id,
            deviceID: RecordingDeviceID(rawValue: deviceID),
            archivedAt: archivedAt,
            archivedByDeviceID: RecordingDeviceID(rawValue: archivedByDeviceID),
        )
    }
}
