import CoreData
import Foundation

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
/// `.NSPersistentStoreRemoteChange` notification — posted by the CloudKit mirror
/// (`NSPersistentCloudKitContainer`) when it imports records synced from another
/// device — into an `AsyncStream`. Observing this notification and re-reading is
/// Apple's documented way to react to remote SwiftData/CloudKit changes.
///
/// One store per app, so it forwards every remote-change notification rather
/// than filtering by coordinator (SwiftData doesn't expose the underlying
/// `NSPersistentStoreCoordinator` to filter on anyway).
final class PersistentStoreRemoteChangeSource: StoreRemoteChangeSource, @unchecked Sendable {
    let remoteChanges: AsyncStream<Void>
    private let center: NotificationCenter
    private let continuation: AsyncStream<Void>.Continuation
    private let observer: NSObjectProtocol

    init(center: NotificationCenter = .default) {
        self.center = center
        var cont: AsyncStream<Void>.Continuation!
        remoteChanges = AsyncStream { cont = $0 }
        continuation = cont
        // Capture the continuation in a local — deliberately *not*
        // `self.continuation` — so the long-lived observer block (which
        // `NotificationCenter` retains until `removeObserver`) doesn't capture
        // `self`. Capturing `self` would keep this source alive for as long as
        // the observer is registered, so `deinit` (which removes it) could
        // never run. The stored `continuation` property exists only for
        // `deinit` to `finish()`.
        let captured = cont!
        observer = center.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: nil,
        ) { _ in
            captured.yield()
        }
    }

    deinit {
        center.removeObserver(observer)
        continuation.finish()
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

        init() {
            var cont: AsyncStream<Void>.Continuation!
            remoteChanges = AsyncStream { cont = $0 }
            continuation = cont
        }

        /// Simulate a remote import: a store observing this source re-pings its
        /// `changes()` fan-out. Named for the `continuation.yield()` it makes.
        func yield() {
            continuation.yield()
        }

        func finish() {
            continuation.finish()
        }
    }
#endif
