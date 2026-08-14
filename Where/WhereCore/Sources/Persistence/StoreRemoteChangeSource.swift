import CoreData
import Foundation
import PeriscopeCore
import SwiftData

/// Abstraction over "the persistent store imported changes from elsewhere" —
/// for a CloudKit-backed store, a sync landing from another device. A
/// `SwiftDataStore` observes one of these and re-pings its `changes()` fan-out,
/// so a remote import refreshes the UI exactly like a local commit (one read
/// path, regardless of who wrote).
///
/// The seam exists so the whole remote-change path is exercisable off-device:
/// production wires `PersistentStoreRemoteChangeSource` (a real Core Data
/// notification observer), tests wire `ScriptedStoreRemoteChangeSource` and call
/// `yield()`. Only Apple's contract — that the CloudKit mirror actually posts
/// the notification on import — stays untested here.
///
/// Class-only (`AnyObject`) because every implementation owns long-lived state
/// (a notification token, an `AsyncStream.Continuation`) that can't be
/// value-copied. Mirrors `LocationSource`.
protocol StoreRemoteChangeSource: AnyObject, Sendable {
    /// Emits once per imported remote change. A bare `Void`: the store re-pings
    /// its fan-out and consumers re-read, so they only need to know *that*
    /// something changed. Exactly one consumer (the store) subscribes, so this
    /// is a single stream rather than a broadcaster.
    var remoteChanges: AsyncStream<Void> { get }
}

/// Production `StoreRemoteChangeSource`: bridges Core Data's
/// `.NSPersistentStoreRemoteChange` notification into an `AsyncStream`. That
/// notification fires both when the CloudKit mirror
/// (`NSPersistentCloudKitContainer`) imports records synced from another device
/// and when a sibling process writes to a shared App Group store (the Where
/// share extension saving evidence) — persistent-history tracking is on for
/// on-disk stores. Observing it and re-reading is Apple's documented way to
/// react to remote SwiftData/CloudKit and cross-process changes.
///
/// Despite its name, Core Data posts the notification for this process's own
/// writes too when persistent-history notifications are enabled. The source
/// therefore stamps local `ModelContext` saves with a per-store author and
/// consults SwiftData history before forwarding only external transactions.
///
/// SwiftData doesn't expose its underlying `NSPersistentStoreCoordinator`, so
/// notifications are scoped by Apple's `NSPersistentStoreURLKey` instead. The
/// app also owns a separate Periscope store; its commits must not masquerade as
/// changes to Where's domain data and trigger a refresh/logging feedback loop.
final class PersistentStoreRemoteChangeSource: NSObject, StoreRemoteChangeSource,
    @unchecked Sendable
{
    private static let logger = WhereLog.root(SwiftDataStoreLog.self)

    let remoteChanges: AsyncStream<Void>

    private let center: NotificationCenter
    private let observedStoreURL: URL
    private let continuation: AsyncStream<Void>.Continuation
    private let candidateContinuation: AsyncStream<Void>.Continuation
    private let classificationTask: Task<Void, Never>

    convenience init(
        modelContainer: ModelContainer,
        storeURL: URL,
        localTransactionAuthor: String,
        center: NotificationCenter,
    ) throws {
        try self.init(
            modelContainer: modelContainer,
            storeURL: storeURL,
            localTransactionAuthor: localTransactionAuthor,
            center: center,
            afterHistoryBaseline: {},
        )
    }

    #if DEBUG
        /// Test seam for committing a transaction in the narrow interval after the history
        /// baseline is captured but before notification observation begins.
        convenience init(
            modelContainer: ModelContainer,
            storeURL: URL,
            localTransactionAuthor: String,
            center: NotificationCenter,
            testingAfterHistoryBaseline: () throws -> Void,
        ) throws {
            try self.init(
                modelContainer: modelContainer,
                storeURL: storeURL,
                localTransactionAuthor: localTransactionAuthor,
                center: center,
                afterHistoryBaseline: testingAfterHistoryBaseline,
            )
        }
    #endif

    private init(
        modelContainer: ModelContainer,
        storeURL: URL,
        localTransactionAuthor: String,
        center: NotificationCenter,
        afterHistoryBaseline: () throws -> Void,
    ) throws {
        self.center = center
        observedStoreURL = storeURL.standardizedFileURL
        let (stream, continuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1),
        )
        remoteChanges = stream
        self.continuation = continuation
        let (candidates, candidateContinuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1),
        )
        self.candidateContinuation = candidateContinuation
        let classifier = try PersistentHistoryRemoteChangeClassifier(
            modelContainer: modelContainer,
            localTransactionAuthor: localTransactionAuthor,
        )
        try afterHistoryBaseline()
        classificationTask = Task {
            for await _ in candidates {
                do {
                    if try await classifier.hasExternalTransactionsSinceLastNotification() {
                        continuation.yield()
                    }
                } catch {
                    // Fail open: a missed remote refresh is less honest than a
                    // duplicate rebuild. Log the classification failure so the
                    // degraded behavior is observable.
                    Self.logger.remoteChangeClassificationFailed(
                        description: .restricted(.errorDetails, error.localizedDescription),
                        attachments: [.error(error, name: "history-error")],
                    )
                    continuation.yield()
                }
            }
        }
        super.init()
        center.addObserver(
            self,
            selector: #selector(persistentStoreDidChange(_:)),
            name: .NSPersistentStoreRemoteChange,
            object: nil,
        )
        // The history baseline necessarily predates target/selector registration. Classify once
        // after registration to close that gap: a transaction committed there already missed its
        // notification, but its durable history row is now visible to this catch-up pass.
        candidateContinuation.yield()
    }

    deinit {
        center.removeObserver(self)
        candidateContinuation.finish()
        classificationTask.cancel()
        continuation.finish()
    }

    @objc private func persistentStoreDidChange(_ notification: Notification) {
        guard let changedStoreURL = notification.userInfo?[NSPersistentStoreURLKey] as? URL,
              changedStoreURL.standardizedFileURL == observedStoreURL
        else { return }
        candidateContinuation.yield()
    }
}

/// Classifies persistent-store notifications through SwiftData history. Core
/// Data posts its so-called remote notification for every write when the option
/// is enabled, including this process's own saves; transaction authors are the
/// durable distinction between those local commits and CloudKit/sibling-process
/// imports.
private actor PersistentHistoryRemoteChangeClassifier {
    private let context: ModelContext
    private let localTransactionAuthor: String
    private var lastTransactionID: Int64

    init(
        modelContainer: ModelContainer,
        localTransactionAuthor: String,
    ) throws {
        let context = ModelContext(modelContainer)
        self.context = context
        self.localTransactionAuthor = localTransactionAuthor
        var latest = HistoryDescriptor<DefaultHistoryTransaction>(
            sortBy: [SortDescriptor(\.transactionIdentifier, order: .reverse)],
        )
        latest.fetchLimit = 1
        lastTransactionID = try context.fetchHistory(latest).first?.transactionIdentifier ?? .min
    }

    func hasExternalTransactionsSinceLastNotification() throws -> Bool {
        let previousTransactionID = lastTransactionID
        let descriptor = HistoryDescriptor<DefaultHistoryTransaction>(
            predicate: #Predicate { transaction in
                transaction.transactionIdentifier > previousTransactionID
            },
        )
        let transactions = try context.fetchHistory(descriptor)
        if let newest = transactions.map(\.transactionIdentifier).max() {
            lastTransactionID = newest
        }
        return transactions.contains { $0.author != localTransactionAuthor }
    }
}

#if DEBUG
    /// Hand-driven `StoreRemoteChangeSource` for tests: `yield()` simulates a
    /// remote import landing, so the store-observes-remote-change path can be
    /// driven deterministically without CloudKit or a device.
    ///
    /// `@_spi(Testing)` + `#if DEBUG` per the agents.md testing-hook convention:
    /// it's test-only scaffolding that mustn't ship in release. Import it with
    /// `@_spi(Testing) @testable import WhereCore` and inject it via
    /// `SwiftDataStore.inMemory(remoteChangeSource:)`.
    @_spi(Testing)
    public final class ScriptedStoreRemoteChangeSource: StoreRemoteChangeSource,
        @unchecked Sendable
    {
        let remoteChanges: AsyncStream<Void>

        private let continuation: AsyncStream<Void>.Continuation

        public init() {
            let (stream, continuation) = AsyncStream.makeStream(
                of: Void.self,
                bufferingPolicy: .bufferingNewest(1),
            )
            remoteChanges = stream
            self.continuation = continuation
        }

        /// Simulate a remote import: a store observing this source re-pings its
        /// `changes()` fan-out. Named for the `continuation.yield()` it makes.
        public func yield() {
            continuation.yield()
        }

        public func finish() {
            continuation.finish()
        }
    }
#endif
