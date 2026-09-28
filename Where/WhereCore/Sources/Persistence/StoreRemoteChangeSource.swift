import Foundation
import Observation
import PeriscopeCore
import SwiftData

/// Abstraction over "the persistent store imported changes from elsewhere" —
/// for a CloudKit-backed store, a sync landing from another device. A
/// `SwiftDataStore` observes one of these and re-pings its `changes()` fan-out,
/// so a remote import refreshes the UI exactly like a local commit (one read
/// path, regardless of who wrote).
///
/// The seam exists so the whole remote-change path is exercisable off-device:
/// production wires `HistoryObserverRemoteChangeSource`, tests wire
/// `ScriptedStoreRemoteChangeSource` and call `yield()`. Only Apple's contract
/// that a CloudKit import reaches SwiftData's history observer stays untested here.
///
/// Class-only (`AnyObject`) because every implementation owns long-lived state
/// (an observation task, an `AsyncStream.Continuation`) that can't be
/// value-copied. Mirrors `LocationSource`.
protocol StoreRemoteChangeSource: AnyObject, Sendable {
    /// Emits once per imported remote change. A bare `Void`: the store re-pings
    /// its fan-out and consumers re-read, so they only need to know *that*
    /// something changed. Exactly one consumer (the store) subscribes, so this
    /// is a single stream rather than a broadcaster.
    var remoteChanges: AsyncStream<Void> { get }
}

/// Production `StoreRemoteChangeSource`: observes SwiftData history for an
/// on-disk container. It covers CloudKit imports and sibling App Group writes.
///
/// `HistoryObserver` filters included authors, but cannot express all authors
/// except this store instance's author. Classify the history rows it reports
/// before forwarding an external-only change.
///
/// The observer is scoped to this `ModelContainer`, so Periscope commits cannot
/// trigger a Where refresh. A history catch-up closes the setup interval between
/// the classifier's baseline and observation startup.
final class HistoryObserverRemoteChangeSource: StoreRemoteChangeSource {
    private static let logger = WhereLog.root(SwiftDataStoreLog.self)

    let remoteChanges: AsyncStream<Void>

    private let observer: HistoryObserver
    private let continuation: AsyncStream<Void>.Continuation
    private let candidateContinuation: AsyncStream<Void>.Continuation
    private let classificationTask: Task<Void, Never>
    private let observationTask: Task<Void, Never>

    convenience init(
        modelContainer: ModelContainer,
        localTransactionAuthor: String,
    ) throws {
        try self.init(
            modelContainer: modelContainer,
            localTransactionAuthor: localTransactionAuthor,
            afterHistoryBaseline: {},
        )
    }

    #if DEBUG
        /// Test seam for committing a transaction in the narrow interval after the history
        /// baseline is captured but before history observation begins.
        convenience init(
            modelContainer: ModelContainer,
            localTransactionAuthor: String,
            testingAfterHistoryBaseline: () throws -> Void,
        ) throws {
            try self.init(
                modelContainer: modelContainer,
                localTransactionAuthor: localTransactionAuthor,
                afterHistoryBaseline: testingAfterHistoryBaseline,
            )
        }
    #endif

    private init(
        modelContainer: ModelContainer,
        localTransactionAuthor: String,
        afterHistoryBaseline: () throws -> Void,
    ) throws {
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
        let observer = try HistoryObserver(modelContainer: modelContainer)
        self.observer = observer
        classificationTask = Task {
            for await _ in candidates {
                do {
                    if try await classifier.hasExternalTransactionsSinceLastCheck() {
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
        let initialCounter = observer.eventCounter
        observationTask = Task {
            var previousCounter = initialCounter
            for await counter in Observations({ observer.eventCounter }) {
                guard counter != previousCounter else { continue }
                previousCounter = counter
                candidateContinuation.yield()
            }
        }
        // A transaction between the history baseline and observation startup
        // may have no event left to deliver. Its durable history row is visible
        // to this catch-up pass.
        candidateContinuation.yield()
    }

    deinit {
        observationTask.cancel()
        candidateContinuation.finish()
        classificationTask.cancel()
        continuation.finish()
    }
}

/// Classifies observed SwiftData history by transaction author so local saves
/// do not duplicate the focused reconciliation their callers already await.
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

    func hasExternalTransactionsSinceLastCheck() throws -> Bool {
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
