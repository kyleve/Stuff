import CoreData
import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

/// The `StoreRemoteChangeSource` seam that makes the CloudKit remote-import path
/// drivable off-device: the scripted double on demand, and the production source
/// from a posted Core Data notification.
struct StoreRemoteChangeSourceTests {
    /// The scripted double yields on `yield()`, so a test can drive the
    /// store-observes-remote-change path deterministically.
    @Test func scriptedSourceYields() async {
        let source = ScriptedStoreRemoteChangeSource()
        let stream = source.remoteChanges

        source.yield()

        #expect(await firstPing(stream, within: .seconds(2)))
    }

    /// The production source forwards a remote-change notification identifying
    /// the Where store it was built to observe.
    @Test func persistentSourceForwardsChangeForItsStore() async {
        let center = NotificationCenter()
        let storeURL = URL(fileURLWithPath: "/Where.store")
        let source = PersistentStoreRemoteChangeSource(storeURL: storeURL, center: center)
        let stream = source.remoteChanges

        withExtendedLifetime(source) {
            center.post(
                name: .NSPersistentStoreRemoteChange,
                object: nil,
                userInfo: [NSPersistentStoreURLKey: storeURL],
            )
        }

        #expect(await firstPing(stream, within: .seconds(2)))
    }

    /// A second SwiftData store in the process (Periscope in the app) also posts
    /// `.NSPersistentStoreRemoteChange`; its commits must not invalidate Where's
    /// data or the resulting refresh spans feed back into more log-store writes.
    @Test func persistentSourceIgnoresChangeForAnotherStore() async {
        let center = NotificationCenter()
        let source = PersistentStoreRemoteChangeSource(
            storeURL: URL(fileURLWithPath: "/Where.store"),
            center: center,
        )
        let stream = source.remoteChanges

        withExtendedLifetime(source) {
            center.post(
                name: .NSPersistentStoreRemoteChange,
                object: nil,
                userInfo: [
                    NSPersistentStoreURLKey: URL(fileURLWithPath: "/Periscope.store"),
                ],
            )
        }

        #expect(await firstPing(stream, within: .milliseconds(200)) == false)
    }
}

/// Awaits the first source emission, returning `false` if none arrives within
/// `budget`. A bounded wait lets rejection tests prove silence without hanging.
private func firstPing(_ stream: AsyncStream<Void>, within budget: Duration) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            for await _ in stream {
                return true
            }
            return false
        }
        group.addTask {
            try? await Task.sleep(for: budget)
            return false
        }
        let result = await group.next() ?? false
        group.cancelAll()
        return result
    }
}
