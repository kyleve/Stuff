import CoreData
import Foundation

/// A persistent-store write signal awaiting origin classification.
///
/// Core Data's `.NSPersistentStoreRemoteChange` name is misleading: Apple
/// documents that it posts for every persistent-store write, including writes
/// from the current process. `SwiftDataStore` therefore classifies production
/// events through SwiftData history before deciding whether to emit its
/// external-only side-effect signal. The scripted case is explicitly external
/// so tests can drive the post-classification path without a persistent store.
enum StoreRemoteChangeEvent {
    case persistentStoreWrite
    case external
}

/// Abstraction over persistent-store write notifications. A `SwiftDataStore`
/// observes one and uses transaction history to separate its own commits from
/// CloudKit or sibling-process writes.
///
/// The seam exists so the whole remote-change path is exercisable off-device:
/// production wires `PersistentStoreRemoteChangeSource` (a real Core Data
/// notification observer), tests wire `ScriptedStoreRemoteChangeSource` and call
/// `yield()`. Only Apple's contract — that the CloudKit mirror actually posts
/// the notification on import — stays untested here.
///
/// Class-only (`AnyObject`) because every implementation owns long-lived state
/// (an observer registration, an `AsyncStream.Continuation`) that can't be
/// value-copied. Mirrors `LocationSource`.
protocol StoreRemoteChangeSource: AnyObject, Sendable {
    /// Emits once per persistent-store notification (production) or explicitly
    /// external test event. Exactly one store consumes this stream.
    var remoteChanges: AsyncStream<StoreRemoteChangeEvent> { get }
}

/// Production `StoreRemoteChangeSource`: bridges Core Data's
/// `.NSPersistentStoreRemoteChange` notification into an `AsyncStream`.
/// Despite its name, the notification fires for every write, including a
/// `ModelContext.save()` in this process. The source deliberately preserves
/// that raw meaning; `SwiftDataStore` checks transaction authors before it
/// calls a write external.
///
/// One store per app, so it forwards every store-write notification rather
/// than filtering by coordinator (SwiftData doesn't expose the underlying
/// `NSPersistentStoreCoordinator` to filter on anyway).
final class PersistentStoreRemoteChangeSource: NSObject, StoreRemoteChangeSource,
    @unchecked Sendable
{
    let remoteChanges: AsyncStream<StoreRemoteChangeEvent>
    private let center: NotificationCenter
    private let continuation: AsyncStream<StoreRemoteChangeEvent>.Continuation

    init(center: NotificationCenter = .default) {
        self.center = center
        var cont: AsyncStream<StoreRemoteChangeEvent>.Continuation!
        remoteChanges = AsyncStream { cont = $0 }
        continuation = cont
        super.init()
        center.addObserver(
            self,
            selector: #selector(persistentStoreDidWrite),
            name: .NSPersistentStoreRemoteChange,
            object: nil,
        )
    }

    @objc private func persistentStoreDidWrite(_: Notification) {
        continuation.yield(.persistentStoreWrite)
    }

    deinit {
        center.removeObserver(self)
        continuation.finish()
    }
}

#if DEBUG
    /// Hand-driven `StoreRemoteChangeSource` for tests: `yield()` sends an
    /// explicitly external event, so the post-classification path can be driven
    /// deterministically without CloudKit or a device.
    ///
    /// `@_spi(Testing)` + `#if DEBUG` per the agents.md testing-hook convention:
    /// it's test-only scaffolding that mustn't ship in release. Import it with
    /// `@_spi(Testing) @testable import WhereCore` and inject it via
    /// `SwiftDataStore.inMemory(remoteChangeSource:)`.
    @_spi(Testing)
    public final class ScriptedStoreRemoteChangeSource: StoreRemoteChangeSource,
        @unchecked Sendable
    {
        let remoteChanges: AsyncStream<StoreRemoteChangeEvent>
        private let continuation: AsyncStream<StoreRemoteChangeEvent>.Continuation

        init() {
            var cont: AsyncStream<StoreRemoteChangeEvent>.Continuation!
            remoteChanges = AsyncStream { cont = $0 }
            continuation = cont
        }

        /// Simulate a change already known to be external. Named for the
        /// continuation operation it performs.
        func yield() {
            continuation.yield(.external)
        }

        func finish() {
            continuation.finish()
        }
    }
#endif
