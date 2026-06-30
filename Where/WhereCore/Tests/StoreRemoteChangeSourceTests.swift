import CoreData
import Foundation
import Testing
@testable import WhereCore

/// The `StoreRemoteChangeSource` seam that makes the CloudKit remote-import path
/// drivable off-device: the scripted double on demand, and the production source
/// from a posted Core Data notification.
struct StoreRemoteChangeSourceTests {
    /// The scripted double yields on `emit()`, so a test can drive the
    /// store-observes-remote-change path deterministically.
    @Test func scriptedSourceYieldsOnEmit() async {
        let source = ScriptedStoreRemoteChangeSource()
        let stream = source.remoteChanges

        source.emit()

        var received = false
        for await _ in stream {
            received = true
            break
        }
        #expect(received)
    }

    /// The production source forwards a posted `.NSPersistentStoreRemoteChange`
    /// (the notification the CloudKit mirror posts on import) into its stream. A
    /// private `NotificationCenter` keeps the test isolated from the default one.
    @Test func persistentSourceForwardsRemoteChangeNotification() async {
        let center = NotificationCenter()
        let source = PersistentStoreRemoteChangeSource(center: center)
        let stream = source.remoteChanges

        center.post(name: .NSPersistentStoreRemoteChange, object: nil)

        var received = false
        for await _ in stream {
            received = true
            break
        }
        #expect(received)
    }
}
