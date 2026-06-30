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
/// `emit()`. Only Apple's contract — that the CloudKit mirror actually posts the
/// notification on import — stays untested here.
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
        let continuation = cont!
        observer = center.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: nil,
        ) { _ in
            continuation.yield()
        }
    }

    deinit {
        center.removeObserver(observer)
        continuation.finish()
    }
}

/// Hand-driven `StoreRemoteChangeSource` for tests and previews: `emit()`
/// simulates a remote import landing, so the store-observes-remote-change path
/// can be driven deterministically without CloudKit or a device.
final class ScriptedStoreRemoteChangeSource: StoreRemoteChangeSource, @unchecked Sendable {
    let remoteChanges: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        var cont: AsyncStream<Void>.Continuation!
        remoteChanges = AsyncStream { cont = $0 }
        continuation = cont
    }

    /// Simulate a remote import: a store observing this source re-pings its
    /// `changes()` fan-out.
    func emit() {
        continuation.yield()
    }

    func finish() {
        continuation.finish()
    }
}
