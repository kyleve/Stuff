import CoreData
import Foundation
import SwiftData
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
    @Test func persistentSourceForwardsExternalAuthorForItsStore() async throws {
        let center = NotificationCenter()
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let storeURL = try #require(container.configurations.first?.url)
        let source = try PersistentStoreRemoteChangeSource(
            modelContainer: container,
            storeURL: storeURL,
            localTransactionAuthor: "where-local",
            center: center,
        )
        let stream = source.remoteChanges
        let external = ModelContext(container)
        external.author = "where-other-process"
        external.insert(SDTrackedRegion(regionID: "us-TX", generationID: .initial))
        try external.save()

        withExtendedLifetime(source) {
            center.post(
                name: .NSPersistentStoreRemoteChange,
                object: nil,
                userInfo: [NSPersistentStoreURLKey: storeURL],
            )
        }

        #expect(await firstPing(stream, within: .seconds(2)))
    }

    /// Observation starts after the initial history cursor is captured. An external commit in
    /// that setup interval has already posted its notification to nobody, so the source must run
    /// one history catch-up after registering rather than waiting for an unrelated later write.
    @Test func persistentSourceCatchesCommitBetweenHistoryBaselineAndObservation() async throws {
        let center = NotificationCenter()
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let storeURL = try #require(container.configurations.first?.url)
        let source = try PersistentStoreRemoteChangeSource(
            modelContainer: container,
            storeURL: storeURL,
            localTransactionAuthor: "where-local",
            center: center,
            testingAfterHistoryBaseline: {
                let external = ModelContext(container)
                external.author = "where-other-process"
                external.insert(SDTrackedRegion(regionID: "us-TX", generationID: .initial))
                try external.save()
            },
        )

        #expect(await firstPing(source.remoteChanges, within: .seconds(2)))
    }

    /// Core Data posts its remote-change notification for the app's own saves
    /// too. The transaction author prevents those local commits from running a
    /// second, full remote reconciliation after their focused one.
    @Test func persistentSourceSuppressesItsLocalTransactionAuthor() async throws {
        let center = NotificationCenter()
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let storeURL = try #require(container.configurations.first?.url)
        let localAuthor = "where-local"
        let source = try PersistentStoreRemoteChangeSource(
            modelContainer: container,
            storeURL: storeURL,
            localTransactionAuthor: localAuthor,
            center: center,
        )
        let stream = source.remoteChanges
        let local = ModelContext(container)
        local.author = localAuthor
        local.insert(SDTrackedRegion(regionID: "us-TX", generationID: .initial))
        try local.save()

        withExtendedLifetime(source) {
            center.post(
                name: .NSPersistentStoreRemoteChange,
                object: nil,
                userInfo: [NSPersistentStoreURLKey: storeURL],
            )
        }

        #expect(await firstPing(stream, within: .milliseconds(200)) == false)
    }

    /// A second SwiftData store in the process (Periscope in the app) also posts
    /// `.NSPersistentStoreRemoteChange`; its commits must not invalidate Where's
    /// data or the resulting refresh spans feed back into more log-store writes.
    @Test func persistentSourceIgnoresChangeForAnotherStore() async throws {
        let center = NotificationCenter()
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let storeURL = try #require(container.configurations.first?.url)
        let source = try PersistentStoreRemoteChangeSource(
            modelContainer: container,
            storeURL: storeURL,
            localTransactionAuthor: "where-local",
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

    /// Target/selector observation must not make the notification center own
    /// the source; otherwise `deinit` can never unregister or finish its tasks.
    @Test func persistentSourceIsNotRetainedByNotificationCenter() throws {
        let center = NotificationCenter()
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let storeURL = try #require(container.configurations.first?.url)
        weak var weakSource: PersistentStoreRemoteChangeSource?

        try autoreleasepool {
            let source = try PersistentStoreRemoteChangeSource(
                modelContainer: container,
                storeURL: storeURL,
                localTransactionAuthor: "where-local",
                center: center,
            )
            weakSource = source
        }

        #expect(weakSource == nil)
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
